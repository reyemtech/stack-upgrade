# Vite + React Upgrade Plan

**Target Vite:** ${TARGET_VITE}
**Target React:** ${TARGET_REACT}
**Date:** ${UPGRADE_DATE}
**Repo:** ${REPO_URL}

## Phases

### Phase 1: React Version Bump + Codemod

Link: https://react.dev/blog/2024/04/25/react-19-upgrade-guide

Upgrade React and React DOM to the target major version and run codemods to handle breaking changes.

**Key steps:**
- Install target React version:
  - npm: `npm install react@${TARGET_REACT} react-dom@${TARGET_REACT}`
  - pnpm: `pnpm add react@${TARGET_REACT} react-dom@${TARGET_REACT}`
  - yarn: `yarn add react@${TARGET_REACT} react-dom@${TARGET_REACT}`
- If TypeScript project (tsconfig.json exists), also update types: `npm install --save-dev @types/react@${TARGET_REACT} @types/react-dom@${TARGET_REACT}`
- Run react-codemod transforms for breaking changes:
  - `npx react-codemod replace-string-literal-ref` — removes deprecated string literal refs
  - `npx react-codemod replace-act-import` — fixes act() import paths
  - `npx react-codemod useFormState` — migrates useFormState → useActionState (if used)
- Commit codemod output separately before any manual fixes (clean history)
- Fix any remaining breakage from the React upgrade
- Verify: `.upgrade/scripts/verify-fast.sh`

### Phase 2: Vite Version Bump + Plugin Update

Link: https://v6.vite.dev/guide/migration

Upgrade Vite and the React plugin to the target major version.

**Key steps:**
- Install target Vite version:
  - npm: `npm install --save-dev vite@${TARGET_VITE} @vitejs/plugin-react@latest`
  - pnpm: `pnpm add -D vite@${TARGET_VITE} @vitejs/plugin-react@latest`
  - yarn: `yarn add -D vite@${TARGET_VITE} @vitejs/plugin-react@latest`
- Update any other Vite plugins to versions compatible with Vite ${TARGET_VITE}:
  - Run `npm outdated` to identify plugins needing updates
  - Update each: vite-plugin-*, @vitejs/*, rollup plugins used in vite.config
- Verify: `.upgrade/scripts/verify-fast.sh`

### Phase 3: Vite Config Format Changes

Link: https://v6.vite.dev/guide/migration

Audit vite.config.js/ts for deprecated and changed options introduced in Vite ${TARGET_VITE}.

**Key steps:**
- Remove `legacy.proxySsrExternalModules` if present (removed in Vite 6)
- Check `resolve.conditions`: if custom values are set, add `...defaultClientConditions` or `...defaultServerConditions` (imported from 'vite') to preserve built-in defaults — Vite 6 no longer merges them automatically
- Check `css.preprocessorOptions.sass.api`: if set to `'legacy'`, remove it — Vite 6 requires the modern Sass API
- Check `json.stringify` and `json.namedExports`: if both are `true`, resolve the conflict (Vite 6 changed their interaction — `json.stringify: true` disables named exports)
- If project uses postcss-load-config with TypeScript (`.postcssrc.ts`), verify postcss-load-config >= 6.0 is installed
- Review any other deprecation warnings produced by `vite build` and address them
- Verify: `vite build` passes cleanly (no warnings about deprecated options)

### Phase 4: TypeScript Types Codemod

Link: https://github.com/eps1lon/types-react-codemod

Update TypeScript React type definitions for React ${TARGET_REACT} breaking type changes.

**SKIP THIS PHASE if `tsconfig.json` does not exist in the project root — this phase only applies to TypeScript projects.**

**Key steps (TypeScript projects only):**
- Confirm tsconfig.json is present: `test -f tsconfig.json && echo "TypeScript project" || echo "JavaScript project — skip"`
- Run the preset for React 19 types: `npx types-react-codemod@latest preset-19 ./src`
- This handles all @types/react v19 breaking type changes (ReactElement default props, ref types, event handler types, etc.)
- Commit the codemod output
- Verify: `npx tsc --noEmit` passes with no type errors
- Verify: `.upgrade/scripts/verify-fast.sh`

### Phase 5: Build Verify + Dependency Cleanup

Link: https://v6.vite.dev/guide/migration

Run full verification, clean up outdated and unused dependencies.

**Key steps:**
- Run full verification: `.upgrade/scripts/verify-full.sh` (lint + tests + tsc + build + npm audit)
- Run `npm outdated` and review remaining outdated packages:
  - Update packages that have non-breaking major updates available
  - Skip packages with known breaking changes that are out of scope
- Remove unused packages (not imported anywhere in src/):
  - Check `.upgrade/recon-report.md` for pre-analyzed usage
  - Log each removal in `.upgrade/run-log.md`
- Final full verification: `.upgrade/scripts/verify-full.sh` must pass cleanly
- Verify: `.upgrade/scripts/verify-full.sh` passes

## Constraints

- Upgrade React and Vite to target major versions — the goal is staying on supported versions
- Never change application behaviour — refactoring for new APIs is fine, changing what code does is not
- Never delete tests — fix them for new APIs
- Skip unused packages — if not imported/used anywhere, remove instead of upgrading
- types-react-codemod only runs on TypeScript projects (check for tsconfig.json)
- If stuck after 3 attempts on same error, log and move on
