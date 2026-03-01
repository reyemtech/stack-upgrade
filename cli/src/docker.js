import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import pc from 'picocolors';
import * as p from '@clack/prompts';
import { deriveName } from './pod-name.js';

/**
 * Check if Docker is available.
 */
export function hasDocker() {
  try {
    execFileSync('docker', ['info'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

/**
 * Pull a Docker image.
 * @param {string} image
 */
function pullImage(image) {
  const pullSpinner = p.spinner();
  pullSpinner.start(`Pulling ${image}...`);
  try {
    execFileSync('docker', ['pull', image], { stdio: 'ignore' });
    pullSpinner.stop('Pulled latest image');
  } catch {
    pullSpinner.stop('Using cached image (pull failed)');
  }
}

/**
 * Launch a single Docker container for an upgrade.
 * @returns {{ containerName: string, outputDir: string }}
 */
function startContainer({ repoUrl, targetVersion, push, suffix, ghToken, claudeCreds, image, stack, envKey }) {
  const containerName = deriveName(repoUrl, stack, targetVersion, suffix);
  const repoShort = repoUrl.replace(/.*[:/]/, '').replace(/\.git$/, '');
  const outputDir = resolve(process.cwd(), 'output', repoShort);

  const args = ['run', '--rm', '-d', '--name', containerName];

  const env = {
    REPO_URL: repoUrl,
    [envKey]: targetVersion,
    GIT_PUSH: push ? 'true' : 'false',
    GH_TOKEN: ghToken,
  };

  if (suffix) env.BRANCH_SUFFIX = suffix;

  if (claudeCreds.type === 'oauth') {
    env.CLAUDE_CODE_OAUTH_TOKEN = claudeCreds.value;
  } else {
    env.ANTHROPIC_API_KEY = claudeCreds.value;
  }

  for (const [key, val] of Object.entries(env)) {
    if (val) args.push('-e', `${key}=${val}`);
  }

  args.push('-v', `${outputDir}:/output`);
  args.push(image);

  execFileSync('docker', args, { stdio: 'ignore' });

  return { containerName, outputDir };
}

/**
 * Launch one or more upgrades as local Docker containers.
 * @param {Array<object>} upgrades - array of upgrade configs
 */
export async function launchDocker(upgrades) {
  // Pull unique images
  const images = [...new Set(upgrades.map((u) => u.image))];
  for (const image of images) {
    pullImage(image);
  }

  // Start all containers
  const launched = [];
  const launchSpinner = p.spinner();
  launchSpinner.start(`Starting ${upgrades.length} ${upgrades.length === 1 ? 'container' : 'containers'}...`);

  try {
    for (const upgrade of upgrades) {
      const result = startContainer(upgrade);
      launched.push({ ...upgrade, ...result });
    }
    launchSpinner.stop(`${launched.length} ${launched.length === 1 ? 'container' : 'containers'} started`);
  } catch (err) {
    launchSpinner.stop('Failed to start container');
    p.log.error(err.message);
    process.exit(1);
  }

  // Summary
  const lines = launched.map((l) => [
    `${pc.bold(l.containerName)}:`,
    `  Logs:   docker logs -f ${l.containerName}`,
    `  Output: ${l.outputDir}/`,
  ].join('\n'));

  p.note(lines.join('\n\n'), `${launched.length} ${launched.length === 1 ? 'upgrade' : 'upgrades'} running!`);
}
