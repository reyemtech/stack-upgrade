# CLAUDE.md — Next.js Upgrade Agent

You are an autonomous Next.js upgrade agent running inside a Docker container.
Your job is to upgrade this Next.js application to the target version specified in `.upgrade/plan.md`.

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
- Include ALL changed files in the phase commit (package.json, lockfile, source files, .upgrade/checklist.yaml, .upgrade/run-log.md, .upgrade/changelog.md, etc.)
- Do NOT make intermediate commits within a phase — one phase = one commit
- Exception: Phase 1 codemod output MUST be committed immediately after running the codemod, before any manual fixes
- Never commit `.env`, `.env.local`, `node_modules/`, or `/output`

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

## Constraints

- **Upgrade to target version** — the goal is staying on supported major versions. Code changes for new APIs are expected.
- **Never change application behaviour** — inputs, outputs, and user-facing features must remain identical. Refactoring code to match a new API is fine; changing what the code *does* is not.
- **Never delete tests** — fix them to work with the new Next.js version
- **`UnsafeUnwrapped` markers and `@next/codemod` comments are BUILD BLOCKERS, not warnings.** The agent must resolve all of them before marking a phase complete. `.upgrade/scripts/verify-fast.sh` exits non-zero if these exist in `src/`, `app/`, or `pages/`.
- **Webpack config migration:** If the project has a custom `webpack:` key in `next.config.js` or `next.config.ts`, either migrate it to the `turbopack:` equivalent OR add `--webpack` to the build command. Next.js 16+ defaults to Turbopack and will ignore the `webpack:` key silently.
- **Skip unused packages** — if a package is in `package.json` but is never imported/used anywhere in the codebase, remove it instead of upgrading. Log the removal in `.upgrade/run-log.md`. Check `.upgrade/recon-report.md` for pre-analyzed package usage.
- **Never force-install** incompatible packages — log the conflict and move on
- If a package has no compatible version, log it in `.upgrade/run-log.md` and skip

## Reference Material

- `.upgrade/nextjs-upgrade-guide.html` — the official Next.js upgrade guide for the target version (if available). **Read this during Phase 1** before running the codemod.
- `.upgrade/recon-report.md` — pre-analyzed repo overview: package usage, component counts, test suite shape

## Verification Scripts

- `.upgrade/scripts/verify-fast.sh` — lint + tests + tsc + grep checks for `UnsafeUnwrapped`/codemod markers (run after every file change)
- `.upgrade/scripts/verify-full.sh` — above + build + npm audit (run before marking any phase complete)

## Useful Commands

```bash
# Run the official codemod (use the target version number)
npx @next/codemod@canary upgrade latest
npx @next/codemod@canary upgrade 15
npx @next/codemod@canary upgrade 16

# Check what the codemod left behind
grep -r "UnsafeUnwrapped\|@next/codemod" src/ app/ pages/ 2>/dev/null

# Build and type-check
next build
npx tsc --noEmit

# Check for deprecations in config
cat next.config.js   # or next.config.ts / next.config.mjs

# Start for smoke testing middleware
next start
curl -I http://localhost:3000/protected-route

# Check package versions
npm outdated
npx npm-check-updates
```

## Middleware Verification Note

Next.js middleware (and, in Next.js 16+, proxy.ts) runs at Edge runtime and **cannot be tested with Jest or Vitest**. After any changes to `middleware.ts` or `proxy.ts`:
1. Run `next build` to catch type errors and config issues
2. Run `next start` in the background
3. Use `curl` against protected routes to verify middleware behaviour (redirect chains, auth headers, etc.)
4. If running `next start` is not feasible in this environment (no ports exposed), document the limitation in `.upgrade/run-log.md` and rely on `next build` for static validation only.

## Error Recovery

If you encounter an error you can't resolve:
1. Document the error, what you tried, and why it failed in `.upgrade/run-log.md`
2. Set the phase status to `failed` in `.upgrade/checklist.yaml`
3. Move to the next phase — a human will review failed phases
4. Do not loop indefinitely on the same problem
