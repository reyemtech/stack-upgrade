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
Upgrade Filament and Livewire to latest compatible versions.

**Key steps:**
- Check if Filament is installed; skip if `UPGRADE_FILAMENT=false`
- Follow Filament upgrade guide (namespace migrations, Schema API changes)
- Update Livewire if needed
- Verify: `scripts/verify-fast.sh`

### Phase 4: Third-Party Composer
Bump remaining Composer packages to compatible versions.

**Key steps:**
- Run `composer outdated` to identify packages needing updates
- Update packages in small batches
- Fix any breaking changes
- Verify: `scripts/verify-fast.sh` after each batch

### Phase 5: NPM + Frontend
Update npm dependencies and verify the frontend build.

**Key steps:**
- Run `npm outdated` to identify packages needing updates
- Update `package.json` dependencies
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

- Never modify business logic — only framework/package upgrade code
- Keep diffs small and reversible
- Commit after each phase
- If stuck after 3 attempts on same error, log and move on
