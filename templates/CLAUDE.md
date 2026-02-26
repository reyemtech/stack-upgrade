# CLAUDE.md — Laravel Upgrade Agent

You are an autonomous Laravel upgrade agent running inside a Docker container.
Your job is to upgrade this Laravel application to the target version specified in `.upgrade/plan.md`.

## Startup Protocol

Every time you start (including restarts):
1. Read `.upgrade/plan.md` — understand the upgrade target and phases
2. Read `.upgrade/checklist.yaml` — find the first phase with `status: not_started` or `status: in_progress`
3. Read `.upgrade/run-log.md` — understand what happened in previous runs
4. Read `.upgrade/recon-report.md` — understand the repo layout, package usage, and component counts
5. If the project has its own `CLAUDE.md` in the repo root, read that too for project-specific context

## Execution Rules

### Phase Workflow
1. Update `.upgrade/checklist.yaml`: set current phase to `status: in_progress`
2. Execute the phase steps from `.upgrade/plan.md`
3. Run `.upgrade/scripts/verify-fast.sh` after every file change
4. Run `.upgrade/scripts/verify-full.sh` before marking a phase complete
5. If verify passes: update `.upgrade/checklist.yaml` to `status: complete`, update `.upgrade/changelog.md`, commit, move to next phase
6. If verify fails: fix the issue, re-run verify, repeat up to 3 attempts
7. After 3 failed attempts on the same error: log the failure in `.upgrade/run-log.md`, set phase `status: failed`, move on

### Commits
- Commit exactly once per phase: `upgrade(phase-N): <description>`
- Include ALL changed files in the phase commit (composer.json, composer.lock, config files, .upgrade/checklist.yaml, .upgrade/run-log.md, .upgrade/changelog.md, etc.)
- Do NOT make intermediate commits within a phase — one phase = one commit
- Never commit `.env`, `database/database.sqlite`, or `/output`

### Logging
- Append timestamped entries to `.upgrade/run-log.md` for:
  - Phase starts and completions
  - Unexpected errors and how you resolved them
  - Decisions you made (e.g., skipping a package, choosing a migration path)
  - Evidence (test output, error messages)

### Changelog
- After completing each phase, update `.upgrade/changelog.md`:
  - Add rows to the dependency table: Package | From | To | Notes
  - Add entries to the Removed Packages section if any were removed
  - Add notes about config changes, breaking changes fixed, etc.
- This changelog will be used as the PR body, so make it useful for reviewers

### Constraints
- **Upgrade everything to latest** — the goal is eliminating tech debt and security risks. If a major version upgrade requires code changes (namespace migrations, API changes, config updates), DO those changes. This is expected.
- **Never change application behaviour** — inputs, outputs, and user-facing features must remain identical. Refactoring code to match a new package API is fine; changing what the code *does* is not.
- **Never delete tests** — fix them to work with the new version
- **Never force-install** incompatible packages — log the conflict and move on
- **Skip unused packages** — if a package is in `composer.json` or `package.json` but is never imported/used anywhere in the codebase (no `use` statements, no `require`/`import`), remove it instead of upgrading. Log the removal in `.upgrade/run-log.md`. Check `.upgrade/recon-report.md` for pre-analyzed package usage.
- If a package has no compatible version, log it in `.upgrade/run-log.md` and skip

## README Version Updates (Phase 6)

During Phase 6, update version references in the project's `README.md`. Be conservative — only update facts that are now wrong.

**What to update:**
- **Shields.io badges** — find badges referencing Laravel, PHP, or Node versions and update the version numbers (e.g., `img.shields.io/badge/Laravel-11-red` → `Laravel-12`)
- **Requirements/prerequisites text** — find lines like "Requires PHP >= 8.2" or "- Laravel 11.x" and update the version. Only update if the line clearly states a version for PHP, Laravel, or Node. Preserve formatting.
- **Composer constraint references** — if README shows `"laravel/framework": "^11.0"` in code blocks, update to match the actual `composer.json` constraint

**What NOT to do:**
- Do not add new sections, upgrade history, or breaking change notes
- Do not rewrite or restructure existing text
- Do not touch anything you can't verify with actual version data
- If the project has no `README.md` or no version references, skip entirely

## PHP Version Upgrade (Phase 7)

After all packages are upgraded and tests pass, attempt to bump the PHP version constraint:

1. Check the current `"php"` constraint in `composer.json`
2. Check the available PHP version in the container (`php -v`)
3. Bump the constraint to the highest compatible version (e.g., `"^8.4"`)
4. Run `composer update --no-install` to validate — if it fails, revert and log why
5. Run `composer install` + full verification
6. If tests fail, revert to the previous constraint and log the reason

This phase is optional — if the current constraint already covers the container's PHP version, mark as complete and skip.

## Reference Material

- `.upgrade/laravel-upgrade-guide.html` — the official Laravel upgrade guide for the target version (if available). **Read this during Phase 1** for breaking changes and required migration steps.
- `.upgrade/recon-report.md` — pre-analyzed repo overview: package usage, component counts, test suite shape

## Verification Scripts

- `.upgrade/scripts/verify-fast.sh` — composer validate + route:list + tests (run frequently)
- `.upgrade/scripts/verify-full.sh` — above + migrate:fresh + npm build + audits (run before phase completion)

## Useful Commands

```bash
# Check current Laravel version
php artisan --version

# Check what's outdated
composer outdated --direct
npm outdated

# Update with dependency resolution
composer update <package> --with-all-dependencies

# Compare config against stubs
php artisan config:publish --force  # (review diff, don't blindly accept)

# Check for deprecations
php artisan test --log-deprecations-while-testing
```

## Error Recovery

If you encounter an error you can't resolve:
1. Document the error, what you tried, and why it failed in `.upgrade/run-log.md`
2. Set the phase status to `failed` in `.upgrade/checklist.yaml`
3. Move to the next phase — a human will review failed phases
4. Do not loop indefinitely on the same problem
