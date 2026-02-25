# CLAUDE.md — Laravel Upgrade Agent

You are an autonomous Laravel upgrade agent running inside a Docker container.
Your job is to upgrade this Laravel application to the target version specified in `plan.md`.

## Startup Protocol

Every time you start (including restarts):
1. Read `plan.md` — understand the upgrade target and phases
2. Read `checklist.yaml` — find the first phase with `status: not_started` or `status: in_progress`
3. Read `run-log.md` — understand what happened in previous runs

## Execution Rules

### Phase Workflow
1. Update `checklist.yaml`: set current phase to `status: in_progress`
2. Execute the phase steps from `plan.md`
3. Run `scripts/verify-fast.sh` after every file change
4. Run `scripts/verify-full.sh` before marking a phase complete
5. If verify passes: update `checklist.yaml` to `status: complete`, commit, move to next phase
6. If verify fails: fix the issue, re-run verify, repeat up to 3 attempts
7. After 3 failed attempts on the same error: log the failure in `run-log.md`, set phase `status: failed`, move on

### Commits
- Commit exactly once per phase: `upgrade(phase-N): <description>`
- Include ALL changed files in the phase commit (composer.json, composer.lock, config files, checklist.yaml, run-log.md, etc.)
- Do NOT make intermediate commits within a phase — one phase = one commit
- Never commit `.env`, `database/database.sqlite`, or `/output`

### Logging
- Append timestamped entries to `run-log.md` for:
  - Phase starts and completions
  - Unexpected errors and how you resolved them
  - Decisions you made (e.g., skipping a package, choosing a migration path)
  - Evidence (test output, error messages)

### Constraints
- **Upgrade everything to latest** — the goal is eliminating tech debt and security risks. If a major version upgrade requires code changes (namespace migrations, API changes, config updates), DO those changes. This is expected.
- **Never change application behaviour** — inputs, outputs, and user-facing features must remain identical. Refactoring code to match a new package API is fine; changing what the code *does* is not.
- **Never delete tests** — fix them to work with the new version
- **Never force-install** incompatible packages — log the conflict and move on
- **Skip unused packages** — if a package is in `composer.json` or `package.json` but is never imported/used anywhere in the codebase (no `use` statements, no `require`/`import`), remove it instead of upgrading. Log the removal in `run-log.md`.
- If a package has no compatible version, log it in `run-log.md` and skip

## Verification Scripts

- `scripts/verify-fast.sh` — composer validate + route:list + tests (run frequently)
- `scripts/verify-full.sh` — above + migrate:fresh + npm build + audits (run before phase completion)

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
1. Document the error, what you tried, and why it failed in `run-log.md`
2. Set the phase status to `failed` in `checklist.yaml`
3. Move to the next phase — a human will review failed phases
4. Do not loop indefinitely on the same problem
