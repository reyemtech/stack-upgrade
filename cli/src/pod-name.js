/**
 * Derive a container/pod name from repo + stack + version + suffix.
 * K8s constraints: lowercase, alphanumeric + dashes, max 63 chars.
 * @param {string} repoUrl
 * @param {string} stack - stack key (e.g., 'laravel')
 * @param {string} targetVersion
 * @param {string} [suffix]
 */
export function deriveName(repoUrl, stack, targetVersion, suffix) {
  const repoShort = repoUrl
    .replace(/.*[:/]/, '')
    .replace(/\.git$/, '')
    .toLowerCase();

  const prefix = stack.charAt(0); // 'l' for laravel, 'r' for react, etc.
  let name = `upgrade-${repoShort}-${prefix}${targetVersion}`;
  if (suffix) {
    name += `-${suffix}`;
  }

  return name
    .toLowerCase()
    .replace(/[^a-z0-9-]/g, '-')
    .replace(/-+/g, '-')
    .replace(/-$/, '')
    .slice(0, 63);
}
