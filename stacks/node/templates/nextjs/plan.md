# Next.js Upgrade Plan

**Target:** Next.js ${TARGET_NEXTJS}
**Date:** ${UPGRADE_DATE}
**Repo:** ${REPO_URL}

## Phases

### Phase 1: Codemod
Run the official Next.js codemod to handle the bulk of mechanical API changes automatically.

Link: https://nextjs.org/docs/app/guides/upgrading/codemods

**Key steps:**
- Read `.upgrade/nextjs-upgrade-guide.html` to understand breaking changes before starting
- Run `npx @next/codemod@canary upgrade ${TARGET_NEXTJS}` — the codemod handles async Request API, import renames, and config key changes
- **Commit the codemod output immediately** in its own commit with message `upgrade(phase-1): run @next/codemod upgrade ${TARGET_NEXTJS}` — do NOT mix manual fixes into this commit
- Do NOT manually fix anything the codemod leaves behind — that is Phase 2's job
- Verify: `.upgrade/scripts/verify-fast.sh` (may fail on `UnsafeUnwrapped` — this is expected at this stage)

### Phase 2: Async Request API Migration
Resolve all `UnsafeUnwrapped` markers and `@next/codemod` comment markers left by the codemod.

Link: https://nextjs.org/docs/app/guides/upgrading/version-15#async-request-apis

**Key steps:**
- Search for all remaining markers: `grep -r "UnsafeUnwrapped\|@next/codemod" src/ app/ pages/ 2>/dev/null`
- For each `UnsafeUnwrapped` type: unwrap the type and add `await` to the property access (e.g., `const { id } = await params`)
- Ensure `params`, `searchParams`, `cookies()`, `headers()`, and `draftMode()` are properly awaited in Server Components and route handlers
- Remove all `@next/codemod` TODO comments after fixing the underlying issue
- Verify: `.upgrade/scripts/verify-fast.sh` — must pass with zero `UnsafeUnwrapped`/codemod markers

### Phase 3: Middleware / Proxy Migration
Handle the middleware.ts → proxy.ts rename for Next.js 16+ and verify Edge runtime configuration.

Link: https://nextjs.org/docs/app/guides/upgrading/version-16

**Key steps:**
- If upgrading to Next.js 16+: check if the codemod renamed `middleware.ts` to `proxy.ts`
- If the project uses Edge runtime explicitly in middleware (`export const runtime = 'edge'`): keep `middleware.ts` — Edge runtime is not supported in `proxy.ts`
- If no Edge runtime usage: confirm the rename is correct and update any imports/references
- Run `next build` to catch type errors in middleware/proxy
- Run `next start` + `curl` against protected routes to smoke test auth/redirect behaviour (see Middleware Verification Note in CLAUDE.md)
- Verify: `next build` passes, middleware/proxy file matches target version convention

### Phase 4: Turbopack Configuration
Migrate Turbopack config keys and handle custom webpack configuration.

Link: https://nextjs.org/docs/app/guides/upgrading/version-16

**Key steps:**
- If `next.config.*` has `experimental.turbopack`: move to top-level `turbopack` key (e.g., `module.exports = { turbopack: { ... } }`)
- If `next.config.*` has a `webpack:` config function: choose one of:
  - Migrate the webpack customisations to their `turbopack:` equivalents (preferred)
  - Add `--webpack` flag to the build script in `package.json` to keep using webpack
- If neither `turbopack` nor `webpack` config exists: no action needed
- Verify: `.upgrade/scripts/verify-fast.sh`

### Phase 5: Cache Semantics Audit
Audit fetch() calls and route segment configs for implicit caching that changed in Next.js 15.

Link: https://nextjs.org/docs/app/guides/upgrading/version-15#caching-semantics

**Key steps:**
- Only required if upgrading from v14 or earlier — Next.js 15 changed the default `fetch()` cache from `force-cache` to `no-store`
- Search for `fetch(` calls without an explicit `cache:` option: `grep -r "fetch(" src/ app/ pages/ 2>/dev/null | grep -v "cache:"`
- For each fetch that previously relied on implicit caching: add `cache: 'force-cache'` or `next: { revalidate: N }` explicitly
- Review route segment configs (`export const revalidate`, `export const dynamic`) and update if needed
- If upgrading from v15 or later: scan for any remaining implicit cache assumptions but this step is likely a no-op
- Verify: `.upgrade/scripts/verify-fast.sh`

### Phase 6: Build Verify + Grep Checks
Full verification pass — ensure the build is clean and all silent-failure markers are resolved.

Link: https://nextjs.org/docs/app/guides/upgrading/version-15

**Key steps:**
- Run `.upgrade/scripts/verify-full.sh` — full build + lint + tests + tsc + grep checks
- Resolve any remaining `UnsafeUnwrapped` or `@next/codemod` markers found by the grep checks
- Fix any remaining deprecated config keys reported in the build output
- Resolve any TypeScript errors (`npx tsc --noEmit`)
- Fix any lint errors (`npx eslint . --max-warnings=0` or `npx biome check .`)
- Verify: `.upgrade/scripts/verify-full.sh` passes clean with exit code 0

### Phase 7: Dependency Cleanup
Update remaining outdated dependencies and remove unused packages.

Link: https://nextjs.org/docs/app/guides/upgrading/version-15

**Key steps:**
- Run `npm outdated` (or `pnpm outdated` / `yarn outdated`) to identify packages needing updates
- Update `react` and `react-dom` to the version required by the target Next.js (check peer deps)
- Update TypeScript type packages: `@types/react`, `@types/react-dom`, `@types/node`
- Update ESLint config: `eslint-config-next` to match the Next.js version
- Remove unused packages — if not imported anywhere in `src/`, `app/`, or `pages/`, remove instead of upgrading
- Run final `.upgrade/scripts/verify-full.sh`
- Verify: no outdated major dependencies, `.upgrade/scripts/verify-full.sh` passes

## Constraints

- Upgrade to target version — the goal is staying on supported major versions
- Never change application behaviour — refactoring for new APIs is fine, changing what code does is not
- UnsafeUnwrapped markers and @next/codemod comments must be fully resolved before Phase 2 is marked complete
- Skip unused packages — if not imported/used anywhere, remove instead of upgrading
- Commit after each phase (Phase 1 has two commits: codemod output + phase completion)
- If stuck after 3 attempts on same error, log and move on
