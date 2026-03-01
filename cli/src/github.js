import { execFileSync } from 'node:child_process';
import * as p from '@clack/prompts';
import { detectStack } from './stacks.js';

/**
 * Get the GitHub auth token from `gh auth token`.
 * @returns {string|null}
 */
export function getGhToken() {
  try {
    return execFileSync('gh', ['auth', 'token'], { encoding: 'utf-8' }).trim();
  } catch {
    return null;
  }
}

/**
 * Get the authenticated GitHub username.
 * @returns {string|null}
 */
export function getGhUser() {
  try {
    const out = execFileSync(
      'gh', ['api', '/user', '--jq', '.login'],
      { encoding: 'utf-8' },
    );
    return out.trim();
  } catch {
    return null;
  }
}

/**
 * List PHP repos the user has access to, detect stack + version.
 * @returns {Promise<Array<{ name: string, url: string, stack: string, stackName: string, version: string }>>}
 */
export async function discoverRepos() {
  // Fetch all PHP repos (owner + collaborator)
  let repos;
  try {
    const out = execFileSync('gh', [
      'api', '/user/repos',
      '--paginate',
      '--jq', '.[] | select(.language == "PHP") | .full_name',
    ], { encoding: 'utf-8', maxBuffer: 10 * 1024 * 1024 });
    repos = out.trim().split('\n').filter(Boolean);
  } catch {
    return [];
  }

  if (repos.length === 0) return [];

  // Check each repo for known stacks (parallel, with concurrency limit)
  const results = [];
  const batchSize = 10;

  for (let i = 0; i < repos.length; i += batchSize) {
    const batch = repos.slice(i, i + batchSize);
    const promises = batch.map(async (fullName) => {
      try {
        const out = execFileSync('gh', [
          'api', `/repos/${fullName}/contents/composer.json`,
          '--jq', '.content',
        ], { encoding: 'utf-8' });

        const content = Buffer.from(out.trim(), 'base64').toString('utf-8');
        const composer = JSON.parse(content);
        const detected = detectStack(composer);
        if (!detected) return null;

        return {
          name: fullName,
          url: `https://github.com/${fullName}.git`,
          stack: detected.stack,
          stackName: detected.stack.charAt(0).toUpperCase() + detected.stack.slice(1),
          version: detected.version,
        };
      } catch {
        return null;
      }
    });

    const batchResults = await Promise.all(promises);
    results.push(...batchResults.filter(Boolean));
  }

  return results;
}

/**
 * Prompt for a manual repo URL and return a repo object.
 * @returns {Promise<{ name: string, url: string, stack: string, version: string }>}
 */
async function promptManualUrl() {
  const url = await p.text({
    message: 'Enter the repository URL:',
    placeholder: 'https://github.com/org/repo.git',
    validate: (v) => {
      if (!v) return 'URL is required';
      if (!v.includes('github.com')) return 'Must be a GitHub URL';
    },
  });
  if (p.isCancel(url)) process.exit(0);

  return { name: url.replace(/.*github\.com[:/]/, '').replace(/\.git$/, ''), url, stack: 'laravel', version: 'unknown' };
}

/**
 * Prompt user to select one or more repos (or enter manually).
 * @param {Array} repos
 * @returns {Promise<Array<{ name: string, url: string, stack: string, version: string }>>}
 */
export async function selectRepos(repos) {
  if (repos.length === 0) {
    const repo = await promptManualUrl();
    return [repo];
  }

  const options = repos.map((r) => ({
    value: r,
    label: r.name,
    hint: `${r.stackName} ${r.version}`,
  }));
  options.push({ value: 'manual', label: 'Enter URL manually' });

  const choices = await p.multiselect({
    message: 'Which repos do you want to upgrade?',
    options,
    required: true,
  });
  if (p.isCancel(choices)) process.exit(0);

  const selected = [];
  for (const choice of choices) {
    if (choice === 'manual') {
      const repo = await promptManualUrl();
      selected.push(repo);
    } else {
      selected.push(choice);
    }
  }

  return selected;
}
