import * as p from '@clack/prompts';

/**
 * Prompt for target version.
 * @param {string} [label='Target version']
 * @returns {Promise<string>}
 */
export async function askTargetVersion(label = 'Target version') {
  const version = await p.text({
    message: label,
    placeholder: '12',
    validate: (v) => {
      if (!v) return 'Version is required';
      if (!/^\d+$/.test(v)) return 'Enter just the major version number (e.g., 12)';
    },
  });
  if (p.isCancel(version)) process.exit(0);
  return version;
}

/**
 * Prompt for push + PR preference.
 * @returns {Promise<boolean>}
 */
export async function askPush() {
  const push = await p.confirm({
    message: 'Push branch and open PR on completion?',
    initialValue: true,
  });
  if (p.isCancel(push)) process.exit(0);
  return push;
}

/**
 * Prompt for optional branch suffix.
 * @returns {Promise<string>}
 */
export async function askSuffix() {
  const today = new Date().toISOString().slice(0, 10);
  const suffix = await p.text({
    message: 'Branch suffix (optional)',
    placeholder: today,
    defaultValue: '',
  });
  if (p.isCancel(suffix)) process.exit(0);
  return suffix;
}

/**
 * Prompt for run target (Docker or Kubernetes).
 * @param {{ hasDocker: boolean, hasKubectl: boolean }} available
 * @returns {Promise<'docker' | 'kubernetes'>}
 */
export async function askRunTarget({ hasDocker, hasKubectl }) {
  const options = [];
  if (hasDocker) options.push({ value: 'docker', label: 'Local Docker' });
  if (hasKubectl) options.push({ value: 'kubernetes', label: 'Kubernetes cluster' });

  if (options.length === 0) {
    p.cancel('Neither docker nor kubectl found in PATH. Install one to continue.');
    process.exit(1);
  }

  if (options.length === 1) return options[0].value;

  const target = await p.select({
    message: 'Where should the upgrade run?',
    options,
  });
  if (p.isCancel(target)) process.exit(0);
  return target;
}
