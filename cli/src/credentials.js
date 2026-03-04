import { readFile, access } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';
import * as p from '@clack/prompts';
import { getConfig, saveConfig } from './config.js';

/**
 * Auto-detect Claude credentials.
 * Priority: saved config > credentials.json > env vars > prompt
 * @param {{ promptIfMissing?: boolean }} options
 * @returns {{ type: 'oauth' | 'apikey', value: string, source: string } | null}
 */
export async function detectClaudeCredentials({ promptIfMissing = true } = {}) {
  // 1. Saved config (~/.stack-upgrade/config.json)
  const saved = getConfig('claudeCredentials');
  if (saved?.value) {
    return {
      type: saved.type,
      value: saved.value,
      source: '~/.stack-upgrade/config.json',
    };
  }

  // 2. ~/.claude/.credentials.json
  try {
    const credPath = join(homedir(), '.claude', '.credentials.json');
    const raw = await readFile(credPath, 'utf-8');
    const creds = JSON.parse(raw);
    const oauth = creds?.claudeAiOauth;
    if (oauth?.accessToken && oauth?.expiresAt > Date.now()) {
      return {
        type: 'oauth',
        value: oauth.accessToken,
        source: '~/.claude/.credentials.json',
      };
    }
  } catch {
    // File doesn't exist or is invalid — continue
  }

  // 3. CLAUDE_CODE_OAUTH_TOKEN env var
  if (process.env.CLAUDE_CODE_OAUTH_TOKEN) {
    return {
      type: 'oauth',
      value: process.env.CLAUDE_CODE_OAUTH_TOKEN,
      source: 'CLAUDE_CODE_OAUTH_TOKEN env var',
    };
  }

  // 4. ANTHROPIC_API_KEY env var
  if (process.env.ANTHROPIC_API_KEY) {
    return {
      type: 'apikey',
      value: process.env.ANTHROPIC_API_KEY,
      source: 'ANTHROPIC_API_KEY env var',
    };
  }

  // 5. Prompt user (or return null if not allowed)
  if (!promptIfMissing) return null;

  const hasClaude = (() => {
    try { execFileSync('which', ['claude'], { stdio: 'ignore' }); return true; } catch { return false; }
  })();

  const method = await p.select({
    message: 'Claude credentials not found. How do you want to authenticate?',
    options: [
      ...(hasClaude ? [{ value: 'setup-token', label: 'Run claude setup-token (recommended)', hint: 'opens browser login' }] : []),
      { value: 'oauth', label: 'Paste OAuth token manually' },
      { value: 'apikey', label: 'Paste API key (Anthropic)' },
    ],
  });
  if (p.isCancel(method)) process.exit(0);

  let result;

  if (method === 'setup-token') {
    p.log.info('Launching claude setup-token...');
    try {
      const output = execFileSync('claude', ['setup-token'], {
        encoding: 'utf-8',
        stdio: ['inherit', 'pipe', 'inherit'],
      });

      const match = output.match(/\b(sk-ant-oat\S+)/);
      if (match) {
        p.log.success('Token captured from setup-token');
        result = { type: 'oauth', value: match[1], source: 'claude setup-token' };
      }
    } catch {
      // fall through
    }

    if (!result) {
      p.log.warn('Could not capture token automatically. Please paste it below.');
      const token = await p.password({ message: 'Paste the OAuth token from above:' });
      if (p.isCancel(token)) process.exit(0);
      result = { type: 'oauth', value: token, source: 'claude setup-token (manual paste)' };
    }
  } else {
    const value = await p.password({
      message: method === 'oauth' ? 'Paste your OAuth token:' : 'Paste your API key:',
    });
    if (p.isCancel(value)) process.exit(0);
    result = { type: method, value, source: 'manual input' };
  }

  // Save to config for next time
  saveConfig({ claudeCredentials: { type: result.type, value: result.value } });
  p.log.success('Credentials saved to ~/.stack-upgrade/config.json');

  return result;
}

/**
 * Auto-detect Codex credentials.
 * Priority: saved config > env vars > ~/.codex/auth.json > prompt
 * @param {{ promptIfMissing?: boolean }} options
 * @returns {{ type: 'apikey' | 'oauth', value: string, source: string } | null}
 */
export async function detectCodexCredentials({ promptIfMissing = true } = {}) {
  // 1. Saved config (~/.stack-upgrade/config.json)
  const saved = getConfig('codexCredentials');
  if (saved?.value) {
    return {
      type: saved.type,
      value: saved.value,
      source: '~/.stack-upgrade/config.json',
    };
  }

  // 2. OPENAI_API_KEY env var
  if (process.env.OPENAI_API_KEY) {
    return {
      type: 'apikey',
      value: process.env.OPENAI_API_KEY,
      source: 'OPENAI_API_KEY env var',
    };
  }

  // 3. ~/.codex/auth.json
  try {
    const authPath = join(homedir(), '.codex', 'auth.json');
    await access(authPath);
    const raw = await readFile(authPath, 'utf-8');
    const b64 = Buffer.from(raw).toString('base64');
    return {
      type: 'oauth',
      value: b64,
      source: '~/.codex/auth.json',
    };
  } catch {
    // File doesn't exist — continue
  }

  // 4. Prompt user (or return null if not allowed)
  if (!promptIfMissing) return null;

  const method = await p.select({
    message: 'Codex credentials not found. How do you want to authenticate?',
    options: [
      { value: 'apikey', label: 'Paste OpenAI API key' },
      { value: 'authjson', label: 'Paste auth.json content (base64)' },
    ],
  });
  if (p.isCancel(method)) process.exit(0);

  let result;

  if (method === 'apikey') {
    const value = await p.password({ message: 'Paste your OpenAI API key:' });
    if (p.isCancel(value)) process.exit(0);
    result = { type: 'apikey', value, source: 'manual input' };
  } else {
    const value = await p.password({ message: 'Paste your auth.json content (base64-encoded):' });
    if (p.isCancel(value)) process.exit(0);
    result = { type: 'oauth', value, source: 'manual input' };
  }

  // Save to config for next time
  saveConfig({ codexCredentials: { type: result.type, value: result.value } });
  p.log.success('Credentials saved to ~/.stack-upgrade/config.json');

  return result;
}
