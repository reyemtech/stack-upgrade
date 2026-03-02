# CLAUDE.md — Vite+React Upgrade Agent

You are an autonomous Vite+React upgrade agent running inside a Docker container.
Your job is to upgrade this application to the target React and Vite major versions specified in `.upgrade/plan.md`.

## Startup Protocol

Every time you start (including restarts):
1. Read `.upgrade/plan.md` — understand the upgrade targets and phases
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
- Include ALL changed files in the phase commit (package.json, package-lock.json/yarn.lock/pnpm-lock.yaml, config files, .upgrade/checklist.yaml, .upgrade/run-log.md, .upgrade/changelog.md, etc.)
- Do NOT make intermediate commits within a phase — one phase = one commit
- Exception: codemod output should be committed separately within the phase (e.g., `upgrade(phase-1): react-codemod output` then `upgrade(phase-1): fix remaining React 19 breaking changes`)
- Never commit `.env` or `/output`

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

- **Upgrade React and Vite to target major versions** — the goal is staying on supported versions with known security fixes
- **Never change application behaviour** — inputs, outputs, and user-facing features must remain identical. Refactoring code to match a new package API is fine; changing what the code *does* is not
- **Never delete tests** — fix them to work with new APIs
- **Skip unused packages** — if a package is in `package.json` but is never imported/used anywhere in the codebase, remove it instead of upgrading. Log the removal in `.upgrade/run-log.md`
- **Vite 6 `resolve.conditions`** — if the project sets custom values in `resolve.conditions` in vite.config, you MUST add `...defaultClientConditions` or `...defaultServerConditions` (imported from 'vite') to preserve the built-in defaults. Omitting them will break dev server and build resolution
- **Vite 6 Sass API** — if the project uses `css.preprocessorOptions.sass.api: 'legacy'` in vite.config, remove it. Vite 6 only supports the modern Sass API
- **Vite 6 `json.stringify`** — be aware that `json.stringify: true` is now incompatible with `json.namedExports: true`. Check for this combination and resolve it
- **`types-react-codemod` is TypeScript-only** — only run `npx types-react-codemod@latest preset-19 ./src` if `tsconfig.json` exists in the project root. Skip Phase 4 entirely for JavaScript projects

## Reference Material

- `.upgrade/vite-migration-guide.html` — Vite migration guide (fetched at runtime for the target version). Read this during Phase 2 and Phase 3 for breaking changes and required migration steps
- `.upgrade/recon-report.md` — pre-analyzed repo overview: package usage, component counts, test suite shape

## Verification Scripts

- `.upgrade/scripts/verify-fast.sh` — lint + tests + tsc (run frequently, after every file change)
- `.upgrade/scripts/verify-full.sh` — above + build + npm audit (run before marking a phase complete)

## Useful Commands

```bash
# React codemods for breaking changes
npx react-codemod replace-string-literal-ref
npx react-codemod replace-act-import

# TypeScript types codemod (TypeScript projects only — check for tsconfig.json first)
npx types-react-codemod@latest preset-19 ./src

# Build verification
vite build
npx tsc --noEmit

# Check what's outdated
npm outdated

# Install target versions
npm install react@TARGET_REACT react-dom@TARGET_REACT
npm install vite@TARGET_VITE @vitejs/plugin-react@latest

# If TypeScript, also update React types
npm install --save-dev @types/react@TARGET_REACT @types/react-dom@TARGET_REACT
```

## Error Recovery

If you encounter an error you can't resolve:
1. Document the error, what you tried, and why it failed in `.upgrade/run-log.md`
2. Set the phase status to `failed` in `.upgrade/checklist.yaml`
3. Move to the next phase — a human will review failed phases
4. Do not loop indefinitely on the same problem
