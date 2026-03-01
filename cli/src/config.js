import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const CONFIG_DIR = join(homedir(), '.stack-upgrade');
const CONFIG_FILE = join(CONFIG_DIR, 'config.json');

/**
 * Load persisted config from ~/.stack-upgrade/config.json.
 * @returns {Record<string, any>}
 */
export function loadConfig() {
  try {
    return JSON.parse(readFileSync(CONFIG_FILE, 'utf-8'));
  } catch {
    return {};
  }
}

/**
 * Save config to ~/.stack-upgrade/config.json (merges with existing).
 * @param {Record<string, any>} updates
 */
export function saveConfig(updates) {
  const existing = loadConfig();
  const merged = { ...existing, ...updates };
  mkdirSync(CONFIG_DIR, { recursive: true });
  writeFileSync(CONFIG_FILE, JSON.stringify(merged, null, 2) + '\n', 'utf-8');
}

/**
 * Get a single config value.
 * @param {string} key
 * @returns {any}
 */
export function getConfig(key) {
  return loadConfig()[key];
}
