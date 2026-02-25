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
- Verify: `scripts/verify-fast.sh`

### Phase 2: First-Party Packages
Upgrade Laravel first-party packages to compatible versions.

**Packages:** Horizon, Telescope, Sanctum, Cashier, Scout, Socialite, Fortify, Jetstream, Breeze, Nightwatch, Pennant, Reverb, Pulse.

**Key steps:**
- Only upgrade packages that exist in `composer.json`
- Use `composer update --with-all-dependencies` for each
- Fix any namespace or API changes
- Verify: `scripts/verify-fast.sh`

### Phase 3: Filament + Livewire
Upgrade Filament and Livewire to their **latest major versions** (e.g., Filament v4/v5, not just patch updates).

**Key steps:**
- Check if Filament is installed; skip if not in `composer.json`
- Upgrade to the latest major version — follow the official upgrade guide
- Apply all required code changes (namespace migrations, Schema API changes, config updates)
- Update Livewire to latest major version if needed
- Check for `livewire/flux` and `livewire/flux-pro` — upgrade if present, skip if not installed
- Verify: `scripts/verify-fast.sh`

### Phase 4: Third-Party Composer
Bump remaining Composer packages to compatible versions.

**Key steps:**
- Run `composer outdated` to identify packages needing updates
- Update packages in small batches
- Fix any breaking changes
- Verify: `scripts/verify-fast.sh` after each batch

### Phase 5: NPM + Frontend
Update ALL npm dependencies to latest major versions and verify the frontend build.

**Key steps:**
- Run `npm outdated` to identify packages needing updates
- Upgrade Tailwind CSS to latest major version (e.g., v4) — follow migration guide
- Update Vite, PostCSS, Autoprefixer, and all build tooling
- Update `package.json` dependencies
- Remove unused packages (not imported anywhere in resources/ or app/)
- Remove deprecated packages
- Verify: `npm run build` + `scripts/verify-fast.sh`

### Phase 6: Config Drift
Reconcile config files against latest Laravel stubs.

**Key steps:**
- Compare config files against `laravel/laravel` stubs for target version
- Add new config keys, remove deprecated ones
- Do NOT override app-specific customizations
- Verify: `scripts/verify-full.sh`

## Constraints

- Upgrade everything to latest major versions — the goal is zero tech debt
- Never change application behaviour — refactoring for new APIs is fine, changing what code does is not
- Skip unused packages — if not imported/used anywhere, remove instead of upgrading
- Commit after each phase
- If stuck after 3 attempts on same error, log and move on
