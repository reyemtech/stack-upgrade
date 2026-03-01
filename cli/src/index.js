#!/usr/bin/env node

import * as p from '@clack/prompts';
import pc from 'picocolors';
import { getGhToken, getGhUser, discoverRepos, selectRepo } from './github.js';
import { detectClaudeCredentials } from './credentials.js';
import { askRunTarget, askTargetVersion, askPush, askSuffix, askAddAnother } from './prompts.js';
import { hasDocker, launchDocker } from './docker.js';
import { hasKubectl, launchKubernetes } from './kubectl.js';
import { getConfig, saveConfig } from './config.js';
import { getStack, STACKS } from './stacks.js';

async function main() {
  p.intro(pc.bold('Stack Upgrade Agent'));

  // --- Prerequisites (auto-detectable) ---
  const preSpinner = p.spinner();
  preSpinner.start('Checking prerequisites...');

  let ghToken = getGhToken();
  if (!ghToken) ghToken = getConfig('ghToken') || null;
  const ghUser = ghToken ? getGhUser() : null;
  const claudeAutoDetect = await detectClaudeCredentials({ promptIfMissing: false });

  if (ghUser) {
    p.log.message(`${pc.green('\u2713')} GitHub CLI authenticated (${ghUser})`);
  } else {
    p.log.message(`${pc.yellow('!')} GitHub CLI not authenticated (will prompt for repo URL)`);
  }

  preSpinner.stop('Prerequisites checked');

  // Claude credentials — prompt after spinner if not auto-detected
  let claudeCreds;
  if (claudeAutoDetect) {
    p.log.message(`${pc.green('\u2713')} Claude credentials found (${claudeAutoDetect.source})`);
    claudeCreds = claudeAutoDetect;
  } else {
    claudeCreds = await detectClaudeCredentials({ promptIfMissing: true });
  }

  // Save GH token if we got one from `gh auth`
  if (ghToken && !getConfig('ghToken')) {
    saveConfig({ ghToken });
  }

  // --- Run target ---
  const dockerAvailable = hasDocker();
  const kubectlAvailable = hasKubectl();
  const savedTarget = getConfig('runTarget');

  let target;
  if (savedTarget && ((savedTarget === 'docker' && dockerAvailable) || (savedTarget === 'kubernetes' && kubectlAvailable))) {
    target = savedTarget;
    p.log.message(`${pc.green('\u2713')} Run target: ${savedTarget === 'docker' ? 'Local Docker' : 'Kubernetes'} (saved)`);
  } else {
    target = await askRunTarget({ hasDocker: dockerAvailable, hasKubectl: kubectlAvailable });
    saveConfig({ runTarget: target });
  }

  // --- Repo discovery ---
  let repos = [];
  if (ghToken) {
    const scanSpinner = p.spinner();
    scanSpinner.start('Scanning your repos...');
    repos = await discoverRepos();
    scanSpinner.stop(`Found ${repos.length} ${repos.length === 1 ? 'repo' : 'repos'}`);
  }

  // --- Shared config ---
  const push = await askPush();
  const suffix = await askSuffix();

  // --- Multi-upgrade loop ---
  const upgrades = [];

  // eslint-disable-next-line no-constant-condition
  while (true) {
    const repo = await selectRepo(repos);

    // Resolve stack
    const stackConfig = getStack(repo.stack);
    if (!stackConfig) {
      p.log.warn(`Unknown stack: ${repo.stack}. Defaulting to Laravel.`);
    }
    const stack = stackConfig || getStack('laravel');

    const targetVersion = await askTargetVersion(stack.versionLabel);

    const branchName = suffix
      ? `${stack.branchPrefix}-${targetVersion}-${suffix}`
      : `${stack.branchPrefix}-${targetVersion}`;

    upgrades.push({
      repoUrl: repo.url,
      repoName: repo.name,
      targetVersion,
      push,
      suffix: suffix || '',
      ghToken,
      claudeCreds,
      image: stack.image,
      stack: repo.stack,
      stackName: stack.name,
      envKey: stack.envKey,
      branchName,
    });

    const another = await askAddAnother();
    if (!another) break;
  }

  // --- Confirmation ---
  const summaryLines = upgrades.map((u, i) =>
    `  ${i + 1}. ${u.repoName}    ${u.stackName} → ${u.targetVersion}    ${target === 'docker' ? 'Local Docker' : 'Kubernetes'}`,
  );

  p.note([
    ...summaryLines,
    '',
    `Push+PR: ${push ? 'yes' : 'no'}${suffix ? `    Suffix: ${suffix}` : ''}`,
  ].join('\n'), `Ready to launch ${upgrades.length} ${upgrades.length === 1 ? 'upgrade' : 'upgrades'}`);

  const confirm = await p.confirm({ message: 'Launch now?' });
  if (p.isCancel(confirm) || !confirm) {
    p.cancel('Aborted.');
    process.exit(0);
  }

  // --- Launch ---
  if (target === 'docker') {
    await launchDocker(upgrades);
  } else {
    await launchKubernetes(upgrades);
  }

  p.outro('Done!');
}

main().catch((err) => {
  if (err.message?.includes('User force closed')) process.exit(0);
  p.cancel(err.message);
  process.exit(1);
});
