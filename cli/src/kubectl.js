import { execFileSync } from 'node:child_process';
import pc from 'picocolors';
import * as p from '@clack/prompts';
import { deriveName } from './pod-name.js';

const SECRET_NAME = 'upgrade-agent';

/**
 * Check if kubectl is available.
 */
export function hasKubectl() {
  try {
    execFileSync('kubectl', ['version', '--client'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

/**
 * List available k8s contexts.
 * @returns {string[]}
 */
function listContexts() {
  try {
    const out = execFileSync('kubectl', ['config', 'get-contexts', '-o', 'name'], { encoding: 'utf-8' });
    return out.trim().split('\n').filter(Boolean);
  } catch {
    return [];
  }
}

/**
 * Get current k8s context.
 * @returns {string|null}
 */
function currentContext() {
  try {
    return execFileSync('kubectl', ['config', 'current-context'], { encoding: 'utf-8' }).trim();
  } catch {
    return null;
  }
}

/**
 * List namespaces in the current context.
 * @returns {string[]}
 */
function listNamespaces() {
  try {
    const out = execFileSync('kubectl', ['get', 'namespaces', '-o', 'jsonpath={.items[*].metadata.name}'], { encoding: 'utf-8' });
    return out.trim().split(/\s+/).filter(Boolean);
  } catch {
    return ['default'];
  }
}

/**
 * Prompt for k8s context selection.
 * @returns {Promise<string>}
 */
async function selectContext() {
  const contexts = listContexts();
  if (contexts.length === 0) {
    p.cancel('No Kubernetes contexts found. Run kubectl config to set one up.');
    process.exit(1);
  }

  if (contexts.length === 1) {
    p.log.info(`Using context: ${contexts[0]}`);
    return contexts[0];
  }

  const current = currentContext();
  const options = contexts.map((c) => ({
    value: c,
    label: c,
    hint: c === current ? 'current' : undefined,
  }));

  const choice = await p.select({
    message: 'Kubernetes context',
    options,
  });
  if (p.isCancel(choice)) process.exit(0);
  return choice;
}

/**
 * Prompt for namespace selection.
 * @returns {Promise<string>}
 */
async function selectNamespace() {
  const namespaces = listNamespaces();
  const common = ['default', 'upgrades'];
  const options = [];

  for (const ns of common) {
    if (namespaces.includes(ns)) {
      options.push({ value: ns, label: ns });
    }
  }
  options.push({ value: '__other', label: 'Other' });

  const choice = await p.select({
    message: 'Kubernetes namespace',
    options,
  });
  if (p.isCancel(choice)) process.exit(0);

  if (choice === '__other') {
    const ns = await p.text({
      message: 'Namespace name:',
      validate: (v) => { if (!v) return 'Required'; },
    });
    if (p.isCancel(ns)) process.exit(0);
    return ns;
  }

  return choice;
}

/**
 * Ensure the upgrade-agent secret exists in the namespace.
 */
function ensureSecret(namespace, ghToken, claudeCreds) {
  try {
    execFileSync('kubectl', ['delete', 'secret', SECRET_NAME, '-n', namespace], { stdio: 'ignore' });
  } catch {
    // Secret didn't exist — nothing to delete
  }

  p.log.info(`Creating secret "${SECRET_NAME}" in namespace "${namespace}"...`);

  const args = [
    'create', 'secret', 'generic', SECRET_NAME,
    '-n', namespace,
  ];

  if (ghToken) {
    args.push(`--from-literal=GH_TOKEN=${ghToken}`);
  }

  if (claudeCreds.type === 'oauth') {
    args.push(`--from-literal=CLAUDE_CODE_OAUTH_TOKEN=${claudeCreds.value}`);
  } else {
    args.push(`--from-literal=ANTHROPIC_API_KEY=${claudeCreds.value}`);
  }

  execFileSync('kubectl', args, { stdio: 'ignore' });
  p.log.success(`Secret created (Claude: ${claudeCreds.type}, GitHub: ${ghToken ? 'yes' : 'no'})`);
}

/**
 * Launch a single pod for an upgrade.
 */
function startPod({ namespace, repoUrl, targetVersion, push, suffix, ghToken, claudeCreds, image, stack, envKey }) {
  const podName = deriveName(repoUrl, stack, targetVersion, suffix);

  const envVars = [
    { name: 'REPO_URL', value: repoUrl },
    { name: envKey, value: targetVersion },
    { name: 'GIT_PUSH', value: push ? 'true' : 'false' },
  ];

  if (suffix) envVars.push({ name: 'BRANCH_SUFFIX', value: suffix });

  // Secret-backed env vars
  const secretEnvs = ['GH_TOKEN', 'CLAUDE_CODE_OAUTH_TOKEN', 'ANTHROPIC_API_KEY'];
  for (const key of secretEnvs) {
    envVars.push({
      name: key,
      valueFrom: { secretKeyRef: { name: SECRET_NAME, key, optional: true } },
    });
  }

  const overrides = JSON.stringify({
    spec: {
      containers: [{
        name: podName,
        image,
        env: envVars,
        resources: {
          requests: { cpu: '1', memory: '2Gi' },
          limits: { cpu: '2', memory: '4Gi' },
        },
      }],
      restartPolicy: 'Never',
    },
  });

  execFileSync('kubectl', [
    'run', podName,
    `--namespace=${namespace}`,
    `--image=${image}`,
    '--restart=Never',
    `--overrides=${overrides}`,
  ], { stdio: 'ignore' });

  return podName;
}

/**
 * Launch one or more upgrades as Kubernetes pods.
 * @param {Array<object>} upgrades - array of upgrade configs
 */
export async function launchKubernetes(upgrades) {
  const context = await selectContext();
  execFileSync('kubectl', ['config', 'use-context', context], { stdio: 'ignore' });

  const namespace = await selectNamespace();

  // Ensure secret (uses first upgrade's creds — they're shared)
  const { ghToken, claudeCreds } = upgrades[0];
  ensureSecret(namespace, ghToken, claudeCreds);

  // Launch all pods
  const launched = [];
  const launchSpinner = p.spinner();
  launchSpinner.start(`Launching ${upgrades.length} ${upgrades.length === 1 ? 'pod' : 'pods'}...`);

  try {
    for (const upgrade of upgrades) {
      const podName = startPod({ ...upgrade, namespace });
      launched.push({ ...upgrade, podName });
    }
    launchSpinner.stop(`${launched.length} ${launched.length === 1 ? 'pod' : 'pods'} created`);
  } catch (err) {
    launchSpinner.stop('Failed to launch pod');
    p.log.error(err.message);
    process.exit(1);
  }

  // Wait for pods to start
  const waitSpinner = p.spinner();
  waitSpinner.start('Waiting for pods to start...');
  for (const { podName } of launched) {
    try {
      execFileSync('kubectl', [
        'wait', '--for=jsonpath={.status.phase}=Running', `pod/${podName}`,
        '-n', namespace, '--timeout=120s',
      ], { stdio: 'ignore' });
    } catch {
      // May still be pulling image
    }
  }
  waitSpinner.stop('Pods running');

  // Summary
  const lines = launched.map((l) => [
    `${pc.bold(l.podName)}:`,
    `  Logs:   kubectl logs -f ${l.podName} -n ${namespace}`,
    `  Status: kubectl get pod ${l.podName} -n ${namespace}`,
    `  Clean:  kubectl delete pod ${l.podName} -n ${namespace}`,
  ].join('\n'));

  p.note(lines.join('\n\n'), `${launched.length} ${launched.length === 1 ? 'pod' : 'pods'} launched!`);
}
