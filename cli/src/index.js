#!/usr/bin/env node

import * as p from '@clack/prompts';
import pc from 'picocolors';
import { getGhToken, getGhUser, discoverRepos, selectRepos } from './github.js';
import { detectClaudeCredentials } from './credentials.js';
import { askRunTarget, askTargetVersion, askPush, askSuffix } from './prompts.js';
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

  // --- Repo selection ---
  const selectedRepos = await selectRepos(repos);

  // Resolve stacks for each repo
  const repoStacks = selectedRepos.map((repo) => {
    const stackConfig = getStack(repo.stack);
    if (!stackConfig) {
      p.log.warn(`Unknown stack: ${repo.stack}. Defaulting to Laravel.`);
    }
    return { repo, stack: stackConfig || getStack('laravel') };
  });

  // If all repos share the same stack, ask target version once; otherwise per-repo
  const uniqueStacks = new Set(repoStacks.map((rs) => rs.repo.stack));
  let sharedVersion = null;
  if (uniqueStacks.size === 1) {
    sharedVersion = await askTargetVersion(repoStacks[0].stack.versionLabel);
  }

  const upgrades = [];
  for (const { repo, stack } of repoStacks) {
    const targetVersion = sharedVersion || await askTargetVersion(`${stack.versionLabel} for ${repo.name}`);
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
  }

  // --- Confirmation ---
  const targetLabel = target === 'docker' ? 'Local Docker' : 'Kubernetes';
  const maxName = Math.max(...upgrades.map((u) => u.repoName.length));
  const maxStack = Math.max(...upgrades.map((u) => `${u.stackName} → ${u.targetVersion}`.length));

  const summaryLines = upgrades.map((u, i) => {
    const name = u.repoName.padEnd(maxName);
    const stack = `${u.stackName} → ${u.targetVersion}`.padEnd(maxStack);
    return `  ${i + 1}. ${name}  ${stack}  ${targetLabel}`;
  });

  p.note([
    ...summaryLines,
    '',
    `Push+PR: ${push ? 'yes' : 'no'}${suffix ? `  Suffix: ${suffix}` : ''}`,
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
