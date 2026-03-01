export const STACKS = {
  laravel: {
    name: 'Laravel',
    image: 'ghcr.io/reyemtech/laravel-upgrade-agent:latest',
    detect: (composer) => composer?.require?.['laravel/framework'],
    versionLabel: 'Target Laravel version',
    branchPrefix: 'upgrade/laravel',
    envKey: 'TARGET_LARAVEL',
  },
};

/**
 * Look up a stack by key.
 * @param {string} key
 * @returns {object|null}
 */
export function getStack(key) {
  return STACKS[key] || null;
}

/**
 * Detect which stack a composer.json belongs to.
 * @param {object} composer - parsed composer.json
 * @returns {{ stack: string, version: string } | null}
 */
export function detectStack(composer) {
  for (const [key, stack] of Object.entries(STACKS)) {
    const dep = stack.detect(composer);
    if (dep) {
      const match = dep.match(/(\d+)/);
      const version = match ? `${match[1]}.x` : dep;
      return { stack: key, version };
    }
  }
  return null;
}
