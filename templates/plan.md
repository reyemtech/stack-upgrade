# Laravel Upgrade Plan

**Target:** Laravel ${TARGET_LARAVEL}
**Date:** ${UPGRADE_DATE}
**Repo:** ${REPO_URL}

## Phases

### Phase 1: Core Framework
Upgrade `laravel/framework` to `^${TARGET_LARAVEL}.0`. Fix all breaking changes from the upgrade guide.

**Key steps:**
- Update `composer.json` constraint
- Run `composer update laravel/framework --with-all-dependencies`
- Fix deprecations and breaking changes per official upgrade guide
- Verify: `.upgrade/scripts/verify-fast.sh`

### Phase 2: First-Party Packages
Upgrade Laravel first-party packages to compatible versions.

**Packages:** Horizon, Telescope, Sanctum, Cashier, Scout, Socialite, Fortify, Jetstream, Breeze, Nightwatch, Pennant, Reverb, Pulse.

**Key steps:**
- Only upgrade packages that exist in `composer.json`
- Use `composer update --with-all-dependencies` for each
- Fix any namespace or API changes
- Verify: `.upgrade/scripts/verify-fast.sh`

### Phase 3: Filament + Livewire
Upgrade Filament and Livewire to their **latest major versions** (e.g., Filament v4/v5, not just patch updates).

**Key steps:**
- Check if Filament is installed; skip if not in `composer.json`
- Upgrade to the latest major version — follow the official upgrade guide
- Apply all required code changes (namespace migrations, Schema API changes, config updates)
- Update Livewire to latest major version if needed
- Check for `livewire/flux` and `livewire/flux-pro` — upgrade if present, skip if not installed
- Verify: `.upgrade/scripts/verify-fast.sh`

### Phase 4: Third-Party Composer
Bump remaining Composer packages to compatible versions.

**Key steps:**
- Run `composer outdated` to identify packages needing updates
- Update packages in small batches
- Fix any breaking changes
- Verify: `.upgrade/scripts/verify-fast.sh` after each batch

### Phase 5: NPM + Frontend
Update ALL npm dependencies to latest major versions and verify the frontend build.

**Key steps:**
- Run `npm outdated` to identify packages needing updates
- Upgrade Tailwind CSS to latest major version (e.g., v4) — follow migration guide
- Update Vite, PostCSS, Autoprefixer, and all build tooling
- Update `package.json` dependencies
- Remove unused packages (not imported anywhere in resources/ or app/)
- Remove deprecated packages
- Verify: `npm run build` + `.upgrade/scripts/verify-fast.sh`

### Phase 6: Config Drift + README
Reconcile config files against latest Laravel stubs and update version references in the project README.

**Key steps:**
- Compare config files against `laravel/laravel` stubs for target version
- Add new config keys, remove deprecated ones
- Do NOT override app-specific customizations
- Update the project `README.md` version references (see README rules below)
- Verify: `.upgrade/scripts/verify-full.sh`

**README update rules (conservative — only update facts that are now wrong):**
- Update shields.io badge version numbers for Laravel, PHP, and Node (e.g., `img.shields.io/badge/Laravel-11-red` → `Laravel-${TARGET_LARAVEL}`)
- Update requirements/prerequisites text that states specific PHP, Laravel, or Node versions
- Update composer constraint references shown in code blocks (e.g., `"laravel/framework": "^11.0"` → `"^${TARGET_LARAVEL}.0"`)
- Do NOT add sections, rewrite prose, or touch anything that isn't a verifiable version number
- If the project has no README.md or no version references, skip this step

### Phase 7: PHP Version
Attempt to bump the PHP version constraint to the latest stable version compatible with all installed dependencies.

**Key steps:**
- Check the current PHP constraint in `composer.json` (e.g., `"php": "^8.2"`)
- Check what PHP version is available in the container (`php -v`)
- Bump the PHP constraint to the highest version compatible with all deps (e.g., `"php": "^8.4"`)
- Run `composer update --no-install` to validate the constraint resolves
- Run `composer install` and `.upgrade/scripts/verify-full.sh`
- If tests fail or constraint doesn't resolve, **revert** to the previous PHP constraint and log the reason
- This phase is optional — if the current constraint already covers the latest PHP, skip it

## Constraints

- Upgrade everything to latest major versions — the goal is zero tech debt
- Never change application behaviour — refactoring for new APIs is fine, changing what code does is not
- Skip unused packages — if not imported/used anywhere, remove instead of upgrading
- Commit after each phase
- If stuck after 3 attempts on same error, log and move on
