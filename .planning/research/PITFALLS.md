# Pitfalls Research

**Domain:** JS Framework Upgrade Agents (Next.js, CRA→Vite, Vite+React, React Native)
**Researched:** 2026-03-01
**Confidence:** MEDIUM (WebSearch verified against official docs where available)

---

## Critical Pitfalls

### Pitfall 1: Next.js — RSC Boundary Violations Treated as Build Errors, Not Runtime Warnings

**What goes wrong:**
When upgrading a Pages Router app to App Router, components that use browser APIs (useState, useEffect, window, document) are implicitly Server Components unless `"use client"` is added at the top. The build fails with cryptic errors like "useState is not a function" or "window is not defined" rather than a clear boundary violation message. An upgrade agent that adds `"use client"` to every component to silence errors produces a working build but completely defeats the purpose of RSC — the app becomes a client-rendered SPA inside an App Router shell.

**Why it happens:**
The direction is strictly server → client. A server component can render client components, but a client component cannot import a server component. You cannot "re-establish" a server boundary beneath a client component via import — only via composition (server parent renders both and passes children via props). Agents that pattern-match "this file uses hooks" → add `"use client"` will add it recursively up the tree and end up marking the entire app as client-only.

**How to avoid:**
- During recon, classify every component as "uses hooks/browser APIs" vs "data-fetching only" and determine the actual boundary points before adding directives.
- `"use client"` should be added at the lowest possible component that actually needs it, not propagated upward.
- After upgrade, verify the RSC payload in the browser DevTools Network tab — look for `text/x-component` responses. If none exist, the App Router migration is a no-op.
- Never add `"use client"` to a file that also has a `"use server"` directive — these are mutually exclusive.

**Warning signs:**
- The agent adds `"use client"` to files that contain only data fetching or layout logic.
- Build succeeds but every route's network tab shows zero RSC payloads.
- The agent recurses: adds `"use client"` to a parent because it imports a child that needed it.

**Phase to address:**
Phase covering Next.js App Router migration (whichever phase handles Pages→App directory restructuring).

---

### Pitfall 2: Next.js — Async Dynamic APIs Break Silently After Codemod Runs

**What goes wrong:**
Next.js 15 made `cookies()`, `headers()`, `draftMode()`, `params`, and `searchParams` asynchronous (they now return Promises). The official codemod handles many cases automatically, but when it cannot determine the correct fix, it inserts `// @next/codemod` comments or `UnsafeUnwrapped` TypeScript casts rather than failing. The build errors out on these markers — but only at build time, not during the codemod run. An agent that runs the codemod and then runs `next build` will see errors, and if it strips the markers without properly awaiting the APIs, silent runtime bugs appear: cookies are undefined, params resolve to `[object Promise]`.

**Why it happens:**
The codemod is AST-based and handles straightforward call patterns. It cannot resolve complex patterns like: the API called inside a conditional, an indirect call through a wrapper function, or a value passed as a prop from a parent that itself is async. These edge cases produce the markers, which must be manually resolved.

**How to avoid:**
- After running `npx @next/codemod@latest upgrade`, search for all `UnsafeUnwrapped` and `@next/codemod` markers and treat each as a required manual fix, not a warning to remove.
- Verify each marker location: does the calling function need to become `async`? Does the caller of that function also need to become `async`?
- Run `next build` with TypeScript strict mode enabled. TypeScript's type system will catch unawaited Promises if types are not suppressed.
- In `verify-fast.sh` for Next.js, check for the presence of `UnsafeUnwrapped` in source files before running the build.

**Warning signs:**
- `grep -r "UnsafeUnwrapped\|@next/codemod" src/` returns hits after the codemod runs.
- `headers()` or `cookies()` calls appear without `await` in async functions.
- Runtime: cookie values are empty strings or undefined despite being set.

**Phase to address:**
Phase 1 (Core Framework — Next.js version bump and codemod application).

---

### Pitfall 3: CRA→Vite — Environment Variables Break Silently at Runtime

**What goes wrong:**
CRA exposes `process.env.REACT_APP_*` variables to client code. Vite uses `import.meta.env.VITE_*`. After migration, any `process.env.REACT_APP_*` reference in source code evaluates to `undefined` at runtime — no build error, no TypeScript error, just a silent undefined. This is the most common source of post-migration failures in production because the app builds and tests pass (if tests are not integration tests that call real APIs), but features that depend on configuration (API base URLs, feature flags, auth keys) silently do nothing or produce 404s.

**Why it happens:**
Vite intentionally does not polyfill `process.env` — it's a Node.js concept that doesn't exist in a browser module context. Vite only exposes `import.meta.env` to client bundles, and only variables prefixed with `VITE_` are included (security-by-default: un-prefixed variables are not leaked to the client). The search-and-replace migration path `REACT_APP_` → `VITE_` in `.env` files is straightforward but easy to miss in `.env.production`, `.env.staging`, or in CI environment variable configuration.

**How to avoid:**
- Recon: before migration, enumerate all `process.env.REACT_APP_` references across all source files and all `.env*` files.
- Replace both: `.env` files (rename keys) AND source code (`process.env.REACT_APP_FOO` → `import.meta.env.VITE_FOO`).
- Check CI/CD pipelines and Kubernetes secrets — these often have `REACT_APP_*` baked in and must be updated separately.
- Add a TypeScript `vite-env.d.ts` that declares the expected `ImportMetaEnv` shape — this makes missing variables a compile error, not a runtime undefined.
- In `verify-fast.sh`, grep the built output for `process.env.REACT_APP` — if any appear in the compiled bundle, the migration is incomplete.

**Warning signs:**
- API calls return 404 or network errors after successful migration.
- Feature flag checks always return false.
- The built JS bundle contains literal strings like `process.env.REACT_APP_API_URL`.

**Phase to address:**
Phase 1 of CRA→Vite migration (config and environment setup).

---

### Pitfall 4: CRA→Vite — Jest to Vitest Migration Takes Longer Than the Vite Migration Itself

**What goes wrong:**
Migrating from CRA to Vite (config files, index.html restructuring, entry point changes) takes hours. Migrating from Jest to Vitest takes days for codebases with significant test suites. The differences accumulate: Vitest does not provide matchers globally by default (need `globals: true` in config), module mock factories must return an object with named exports explicitly (Jest's default export shortcut doesn't work), JSX files must have `.jsx`/`.tsx` extensions not `.js`/`.ts`, and `jest` as a global identifier doesn't exist (every `jest.fn()` must become `vi.fn()`). An agent that finishes the Vite migration and then starts the Jest→Vitest migration often gets stuck in a retry loop fixing individual test failures, each fix revealing the next class of failure.

**Why it happens:**
Jest and Vitest have similar but non-identical APIs. Codemods exist (Vitest 4 in October 2025 added better codemods) but they don't handle: complex mock factories, custom Jest matchers/setup files, `jest.useFakeTimers()` (Vitest no longer has a default list — only specified timers are faked), and project-specific `jest.config.js` configuration like `moduleNameMapper`.

**How to avoid:**
- Treat the Jest→Vitest migration as a separate phase from the Vite config migration. Do not block build verification on test migration.
- Run the codemod first (`npx @vitest/codemod`), then address remaining failures in categories: globals, mock factories, timer fakes, path aliases.
- Keep Jest running alongside Vitest temporarily using a separate test script entry in `package.json` — this prevents losing test coverage entirely during migration.
- Document each class of failure in `run-log.md` before attempting fixes, to avoid thrashing on individual tests.
- Cap retries: if the same test-migration pattern fails 3 times, log the category, skip it, and move on (ralph loop pattern).

**Warning signs:**
- More than 10% of tests fail after the codemod runs.
- The agent repeatedly touches the same test file across multiple iterations.
- `vi is not defined` or `jest is not defined` errors in test output.

**Phase to address:**
Dedicated test migration phase (after Vite config phase, before NPM/build verification phase).

---

### Pitfall 5: React Native — Native Module Binary Incompatibility After Version Bump

**What goes wrong:**
React Native native modules (those with native iOS/Android code) must be recompiled against the target RN version. When the RN version is bumped in `package.json` and `yarn install` or `npm install` runs, the JS layer updates but the native binaries (`.a` files in iOS, `.aar` files in Android, or autolinking bindings) are stale. The build fails with linker errors, missing symbol errors, or the module loads at runtime and immediately crashes. Common offenders: `react-native-reanimated`, `react-native-screens`, `react-native-gesture-handler`, `@react-native-camera/camera`. The failures are platform-specific — the Android build may succeed while iOS fails, or vice versa.

**Why it happens:**
React Native autolinking regenerates native bindings based on what's in `node_modules`, but the bindings must match the RN core version. When CocoaPods or Gradle caches contain stale artifacts from the previous version, the fresh autolinking bindings conflict with the cached native builds. Additionally, since RN 0.82, the New Architecture is permanently enabled — libraries that haven't migrated to TurboModules and Fabric will fail with interop layer errors or simply not function.

**How to avoid:**
- After `npm install` / `yarn install` with new RN version: always run `cd ios && pod deintegrate && pod install` (full deintegrate, not just install) to rebuild CocoaPods from scratch.
- For Android: run `./gradlew clean` before building.
- Check every native module against React Native Directory (reactnative.directory) for New Architecture compatibility before upgrading — incompatible modules will cause builds that appear to succeed but crash at app launch.
- Delete `ios/Pods/`, `ios/Podfile.lock`, `android/.gradle/`, and `android/build/` before the first build post-upgrade.
- The verify script for React Native must build both platforms, not just run `jest`.

**Warning signs:**
- `pod install` completes but `xcodebuild` fails with "symbol not found" or "file not found."
- Gradle builds with `BUILD SUCCESSFUL` but app crashes immediately on device.
- A library that was working before the upgrade now throws `TurboModule not found` at runtime.

**Phase to address:**
Phase 1 (RN version bump) and Phase 2 (native dependency audit and rebuild).

---

### Pitfall 6: React Native — Gradle Plugin Version Mismatch Causes Android Build Failure

**What goes wrong:**
React Native specifies a required Android Gradle Plugin (AGP) version and a minimum Gradle wrapper version. These are version-locked per RN release. When RN is upgraded, if `android/build.gradle` (AGP version) and `android/gradle/wrapper/gradle-wrapper.properties` (Gradle wrapper version) are not updated in sync, the Android build fails with errors like "Minimum supported Gradle version is X. Current version is Y." or "The project is using an incompatible version (AGP 8.X) of the Android Gradle plugin." The React Native Upgrade Helper provides the correct diff, but an agent that only updates `package.json` and re-runs `npm install` will never touch these Gradle files.

**Why it happens:**
Gradle wrapper versions and AGP versions are not managed by npm — they live in the Android project directory as plain text files. Automated dependency managers (Renovate, Dependabot) do not update Gradle wrapper files when the triggering change is an npm package bump. The RN upgrade process explicitly requires consulting the `android/` diff from the React Native Upgrade Helper, which an agent may not know to do.

**How to avoid:**
- During recon, extract the current AGP version from `android/build.gradle` and the Gradle wrapper version from `android/gradle/wrapper/gradle-wrapper.properties`.
- After bumping RN version, look up the required AGP/Gradle versions in the RN release notes or Upgrade Helper diff and update both files explicitly.
- Add a recon check: does the current Gradle wrapper version meet the minimum for the target RN version? If not, flag it before attempting the upgrade.
- In `verify-fast.sh` for RN, run `./gradlew --version` and compare against the documented minimum.

**Warning signs:**
- Android build errors mentioning "Minimum supported Gradle version."
- `android/gradle/wrapper/gradle-wrapper.properties` still shows the old RN's default version after the package bump.
- `classpath 'com.android.tools.build:gradle:X.X.X'` in `android/build.gradle` doesn't match the AGP version required by the new RN.

**Phase to address:**
Phase 1 (RN version bump) — must be done as part of the same commit as the npm version update.

---

### Pitfall 7: Next.js — Caching Semantics Inversion Causes Data-Freshness Regressions After Upgrade to v15+

**What goes wrong:**
In Next.js 14 and earlier, `fetch()` requests defaulted to `force-cache`. In Next.js 15, the default flipped to `no-store`. GET Route Handlers are also no longer cached by default. After upgrading, pages that previously displayed fresh data may start serving stale cached data (if explicit cache settings were added assuming the old default), while pages that depended on the old force-cache default now make a network request on every render, causing performance regressions or upstream rate limiting. Both failure modes are silent — the build succeeds and automated tests that mock `fetch` don't catch the change.

**Why it happens:**
The caching behavior is set by the `cache` option on individual `fetch()` calls (or by route segment config). Before v15, omitting `cache` meant `force-cache`. After v15, omitting `cache` means `no-store`. Code that was written assuming one default now behaves differently without any syntax change.

**How to avoid:**
- During recon, grep all `fetch(` calls and route handlers for explicit `cache` options. Flag any without an explicit setting — these will change behavior after upgrade.
- After upgrading, add explicit `cache` options to every `fetch()` call that should be cached. Do not rely on the default in either direction.
- For Route Handlers that must be cached, add `export const dynamic = 'force-static'` explicitly.
- Integration tests should test actual cache behavior (or at least assert the `cache` option is set), not just mock fetch responses.

**Warning signs:**
- API rate limit errors appear in production after upgrade (previously cached requests now hit the API on every render).
- Upstream services report traffic spikes after deployment.
- Pages that showed real-time data now show stale data (some teams had added `force-cache` explicitly, expecting the data to be refreshed by ISR revalidation).

**Phase to address:**
Phase 1 (Next.js version bump) — add explicit cache opts as part of the bump, before any other changes.

---

### Pitfall 8: Next.js — Middleware Runtime and Breaking Changes Missed Because Middleware Is Tested Last

**What goes wrong:**
Next.js middleware runs at the Edge runtime by default. Between major versions, middleware APIs have changed: `NextResponse.rewrite()` behavior, `middleware.ts` file location, the matcher config format, and cookie/header mutation APIs. An upgrade agent that defers middleware testing (because middleware doesn't appear in unit tests) will complete all phases, push the branch, and create the PR — only for QA to discover that auth redirects, A/B testing logic, or rate limiting is broken in the deployed preview environment.

**Why it happens:**
Middleware is not tested by Jest/Vitest (it runs in a non-standard Edge runtime environment). Integration tests that cover middleware behavior are rare. The middleware file is often a single file (`middleware.ts`) that appears unchanged by the linter and type-checker even after breaking API changes.

**How to avoid:**
- Add middleware-specific verification to `verify-fast.sh`: use `next build` and check that the built middleware bundle has no errors in the build output.
- During recon, identify all middleware files, extract the matcher configuration, and document what routes they intercept.
- After upgrade, test middleware behavior manually or via playwright/cypress with a local `next start` — not just `next dev`.
- Check the Next.js upgrade guide specifically for middleware changes (they are documented per version).

**Warning signs:**
- `middleware.ts` exists in the project but is not referenced in any test file.
- The upgrade guide for the target version mentions "middleware changes" — this is common.
- The build output shows warnings about deprecated middleware APIs.

**Phase to address:**
Phase 1 (version bump) — middleware must be explicitly addressed, not assumed to be covered by passing tests.

---

### Pitfall 9: Vite+React — Plugin Incompatibility and Fast Refresh Failures After Major Vite Bump

**What goes wrong:**
Vite plugin APIs change between major versions. After a Vite major bump (e.g., v5→v6 or v6→v7/v8), plugins that worked previously may silently stop working, produce warnings that are ignored, or break Fast Refresh (HMR). The canonical failure: after a Vite upgrade, the dev server starts and builds succeed, but React Fast Refresh stops working — changes to a component require a full page reload, which developers notice only during development, not in CI. A more serious failure: certain plugins stop transforming files correctly and the error only surfaces as a runtime exception on specific user paths.

**Why it happens:**
Vite's plugin hooks have changed between major versions. Vite 6 removed the `modules` default target and replaced it with `baseline-widely-available`. Vite 6 also removed the Sass legacy API. Plugins that relied on internal Vite APIs or the old target behavior break silently when the target behavior changes.

**How to avoid:**
- During recon, enumerate all Vite plugins in `vite.config.ts`. For each, check its npm page for the latest version and whether it has a documented compatibility matrix with the target Vite version.
- After upgrade, run `vite build` and check for plugin-related deprecation warnings — treat any warning about removed APIs as a blocking failure.
- Verify Fast Refresh explicitly: start `vite dev`, open a route, modify a component, and confirm the change hot-reloads without a full page reload.
- In `verify-fast.sh` for Vite, include a build step that checks for deprecated API warnings in the output.

**Warning signs:**
- `vite build` output contains "deprecated" or "plugin X does not support Vite X" warnings.
- The `@vitejs/plugin-react` package version in `package.json` does not match the peer dependency requirement of the installed Vite version.
- Fast Refresh stops working in dev mode but builds still succeed.

**Phase to address:**
Phase covering Vite config and plugin compatibility (before React version bump, since plugin compatibility must be resolved first).

---

### Pitfall 10: React Native — New Architecture Permanently Enabled in RN 0.82+ Breaks Libraries That Haven't Migrated

**What goes wrong:**
Starting with React Native 0.82, the New Architecture (Fabric renderer + TurboModules + JSI) is permanently enabled and cannot be disabled. Libraries that depended on the Bridge (the old architecture's IPC layer) will fail at runtime — they load, but their native module calls silently return undefined or throw "NativeModule X is null." The interop layer (enabled since 0.74) handles many libraries without changes, but libraries with hand-written native module bindings or custom renderers require explicit New Architecture support. The "State of React Native" survey from early 2025 confirmed third-party library compatibility as developers' #1 pain point.

**Why it happens:**
Historically, library authors supported both architectures with a conditional version check. With 0.82+, the interop layer was not removed, but the path to disable New Architecture was. Libraries that haven't published a version with TurboModule specs (`NativeModule.js` + Codegen spec) will not work even with the interop layer.

**How to avoid:**
- During recon, extract all npm packages with native bindings (check for `ios/` or `android/` directories in `node_modules/<package>` — or check `package.json` for `"native"` in keywords).
- For each native module, check React Native Directory (reactnative.directory) for New Architecture compatibility status before upgrading RN.
- Packages marked "Untested" or "Not supported" on RN Directory are high-risk blockers — plan alternatives or forks before starting the upgrade.
- After `pod install` / `gradlew build`, check the build output for Codegen-related warnings about missing specs.

**Warning signs:**
- `NativeModule X is null` logged to the console immediately after app launch.
- A native module that worked in the previous RN version throws "Cannot read property of null" from native code.
- React Native Directory shows the library as "Not supported" for New Architecture.

**Phase to address:**
Phase 0 (pre-upgrade audit) — identify incompatible libraries before any version changes.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Add `"use client"` to every Next.js component | Silences all RSC boundary errors immediately | Entire app renders on client — no server components, no RSC payload, wasted the App Router migration | Never |
| Use `vite-plugin-env-compatible` to keep `REACT_APP_` prefix | Avoids renaming env vars | Plugin dependency forever, blocks future Vite upgrades, masks the real migration | Only as temporary bridge during incremental migration |
| Skip Jest→Vitest migration, keep Jest alongside Vite | Unblocks the Vite migration | Two test runners, conflicting configs, eventual breakage when CRA polyfills are removed | Acceptable for Phase 1, must be resolved in subsequent phase |
| Skip `pod deintegrate` and just run `pod install` | Faster iOS build step | Stale pod artifacts cause intermittent build failures | Never — always full deintegrate on RN major bumps |
| Bump RN version without consulting Upgrade Helper diff | Faster upgrade | Gradle/AGP mismatch, missing template changes in `android/` and `ios/` | Never |
| Explicit `cache: 'force-cache'` on all fetch calls post-Next 15 | Restores pre-v15 caching behavior | Stale data everywhere, defeats the reason Next.js changed the default | Only as a temporary compatibility measure while per-call cache strategy is planned |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| CI/CD env vars (CRA→Vite) | Only rename vars in `.env` files, not in CI pipeline secrets | Audit every CI environment (GitHub Actions, CircleCI, Vercel, Netlify) for `REACT_APP_*` variables and rename them to `VITE_*` |
| Next.js + Auth libraries (Clerk, NextAuth) | Auth libraries often use middleware and cookies — upgrade path is library-version-specific | Check the auth library's Next.js 15 migration guide specifically; do not assume a simple version bump suffices |
| React Native + Reanimated | Old Reanimated versions don't support New Architecture — causes build failures and runtime crashes | Must upgrade Reanimated to 3.x+ before or alongside the RN upgrade |
| React Native + Flipper | Flipper integration removed from RN 0.73+ — old Podfile configs that reference Flipper cause pod install failures | Remove all Flipper-related lines from `Podfile` and `android/app/build.gradle` during upgrade |
| Vite + Tailwind CSS | Tailwind v4 uses a Vite plugin instead of PostCSS config — both methods co-existing causes duplicate processing | Remove PostCSS Tailwind config when adding the Vite plugin, not both simultaneously |
| CRA proxy config | CRA's `"proxy"` field in `package.json` has no equivalent in Vite | Replace with Vite's `server.proxy` in `vite.config.ts`; note the config format is different |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Next.js: no explicit cache on data-heavy pages after v15 upgrade | Pages make database/API calls on every request instead of using ISR | Add explicit `cache` and `revalidate` options to all data-fetching calls | Immediately after upgrade to v15+ in production |
| Vite: bundling everything into one chunk after CRA migration | First load is large; CRA split automatically, Vite doesn't by default | Configure `build.rollupOptions.output.manualChunks` for vendor splitting | Not until production load — dev bundle is always merged |
| React Native: not enabling Hermes (if not already enabled) | App startup time 2-3x slower on Android; larger bundle | Hermes is default from 0.76+ — if upgrading from below 0.76, explicitly enable it | Immediately visible in startup benchmarks |
| Next.js: Suspense boundaries placed inside async components | Suspense boundary has no effect if placed inside the component that suspends | Place Suspense boundaries in the parent component, above the async child | Streaming and loading states don't work at runtime |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Leaking non-VITE_ prefixed variables in Vite build | Server-only secrets (DB connection strings, private API keys) accidentally exposed to client bundle | Vite's default behavior prevents this, but `loadEnv` called with `''` prefix exposes everything — never do this |
| Next.js RSC: passing sensitive server data through component props to client components | Data appears in RSC payload (visible in Network tab) | Server-only data must stay server-only; use `server-only` npm package to enforce import restrictions |
| Not updating to patched Next.js version with RSC RCE fix | CVE-2025-66478 / CVE-2025-55182: unauthenticated RCE via insecure RSC deserialization | Target Next.js 15.0.5+, 15.1.9+, 15.2.6+, etc. — any version below these is exploitable |
| React Native: including sensitive env vars in Metro bundle | Values baked into JS bundle, visible with `strings` on the binary | Use a native secrets module (react-native-dotenv with native bindings, or environment-specific configs from native layer) |

---

## "Looks Done But Isn't" Checklist

- [ ] **Next.js RSC Migration:** Verify at least one route produces RSC payload (`text/x-component` in Network tab) — if none, `"use client"` was added too broadly.
- [ ] **CRA→Vite env vars:** Run `grep -r "process\.env\.REACT_APP_" dist/` after build — any hit means env var migration is incomplete.
- [ ] **CRA→Vite proxy:** Test a dev-server API proxy request — Vite's `server.proxy` is different from CRA's `"proxy"` field and must be verified manually.
- [ ] **Next.js codemod:** Run `grep -r "UnsafeUnwrapped\|@next/codemod" src/` — any hit means the codemod left markers that require manual resolution.
- [ ] **React Native iOS:** Verify `pod deintegrate && pod install` ran (not just `pod install`) — stale pods from the old RN version may be present.
- [ ] **React Native Android:** Verify `./gradlew clean build` ran after Gradle/AGP version update — cached artifacts from old versions cause intermittent failures.
- [ ] **React Native New Architecture:** Check every native module against RN Directory for New Architecture compatibility — presence in `node_modules` does not mean it works.
- [ ] **Vitest migration:** Run `grep -r "jest\." src/` on test files — any hit means `jest` global references remain, which fail at runtime (not compile time).
- [ ] **Next.js caching:** After v15 upgrade, run `grep -r "cache:" src/` — every data-fetching `fetch()` call without an explicit `cache` option now defaults to `no-store`.
- [ ] **Vite plugin compatibility:** Check `vite build` output for plugin deprecation warnings — these are non-fatal but indicate plugins that will break in the next Vite version.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| `"use client"` added too broadly in Next.js App Router | HIGH | Audit component tree from leaves to root; remove `"use client"` from pure data components; test RSC payload in Network tab after each removal |
| Env var prefix migration incomplete (CRA→Vite) | LOW | Grep for `process.env.REACT_APP_` in source and dist; rename remaining variables; redeploy CI secrets |
| Next.js codemod markers left in source | MEDIUM | `grep -r "@next/codemod\|UnsafeUnwrapped"` to find all; resolve each by properly awaiting the async API; re-run `next build` |
| Stale CocoaPods artifacts (React Native) | LOW | `cd ios && pod deintegrate && pod cache clean --all && pod install` |
| Gradle/AGP version mismatch (React Native) | LOW | Update `android/build.gradle` AGP version and `gradle-wrapper.properties` Gradle version per RN release notes; run `./gradlew clean` |
| New Architecture incompatible library (React Native) | HIGH | Find alternative library; fork and add TurboModule spec; or pin RN to a version below 0.82 (last resort, temporary) |
| Vitest migration stalled on complex mock patterns | MEDIUM | Document failing mock patterns in run-log.md; keep Jest as parallel runner; migrate mocks category by category rather than file by file |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| RSC boundary violations (Next.js) | Phase: App Router migration | Network tab shows RSC payloads; no `"use client"` on pure server components |
| Async dynamic APIs post-codemod (Next.js) | Phase 1: version bump + codemod | `grep -r "UnsafeUnwrapped"` returns empty; `next build` clean |
| Env var prefix break (CRA→Vite) | Phase 1: Vite config migration | `grep -r "process\.env\.REACT_APP_" dist/` returns empty |
| Jest→Vitest migration stall (CRA) | Dedicated test phase (after Vite config) | All tests pass under Vitest; no Jest config remains |
| Native binary incompatibility (RN) | Phase 1: RN version bump | iOS `xcodebuild` and Android `gradlew build` both succeed from clean state |
| Gradle/AGP mismatch (RN) | Phase 1: RN version bump | `./gradlew --version` meets documented minimum for target RN |
| Caching semantics inversion (Next.js 15) | Phase 1: version bump | Every `fetch()` has explicit `cache` option; no implicit defaults relied upon |
| Middleware breaking changes (Next.js) | Phase 1: version bump | Middleware-specific routes tested via `next start` integration test |
| Vite plugin incompatibility | Phase: Vite config migration | `vite build` output has no plugin deprecation warnings; Fast Refresh verified |
| New Architecture library incompatibility (RN) | Phase 0: pre-upgrade audit | Every native module verified against RN Directory before version bump |

---

## Sources

- [Next.js App Router Migration Guide](https://nextjs.org/docs/app/guides/migrating/app-router-migration) — HIGH confidence (official docs)
- [Next.js Version 15 Upgrade Guide](https://nextjs.org/docs/app/guides/upgrading/version-15) — HIGH confidence (official docs)
- [Next.js Version 16 Upgrade Guide](https://nextjs.org/docs/app/guides/upgrading/version-16) — HIGH confidence (official docs)
- [Next.js Codemods Guide](https://nextjs.org/docs/app/guides/upgrading/codemods) — HIGH confidence (official docs)
- [Next.js Dynamic APIs are Asynchronous](https://nextjs.org/docs/messages/sync-dynamic-apis) — HIGH confidence (official docs)
- [Common mistakes with the Next.js App Router — Vercel](https://vercel.com/blog/common-mistakes-with-the-next-js-app-router-and-how-to-fix-them) — MEDIUM confidence (official vendor blog)
- [Next.js Security Advisory CVE-2025-66478](https://nextjs.org/blog/CVE-2025-66478) — HIGH confidence (official advisory)
- [CRA to Vite migration — Robin Wieruch](https://www.robinwieruch.de/vite-create-react-app/) — MEDIUM confidence (widely referenced community guide)
- [Migrating CRA to Vite — Peerlist](https://peerlist.io/rutik45/articles/migrating-from-create-react-app-cra-to-vite-common-issues-an) — MEDIUM confidence (practitioner writeup)
- [Lessons Learned: CRA + Jest to Vite + Vitest — DEV Community](https://dev.to/dsychin/lessons-learned-migrating-from-cra-jest-to-vite-vitest-4ahe) — MEDIUM confidence (practitioner post-mortem)
- [Migrating from Jest to Vitest — Vitest Official Guide](https://vitest.dev/guide/migration.html) — HIGH confidence (official docs)
- [Vite 6 Migration Guide](https://vite.dev/guide/migration) — HIGH confidence (official docs)
- [React Native 0.82 Release Notes](https://reactnative.dev/blog/2025/10/08/react-native-0.82) — HIGH confidence (official blog)
- [React Native New Architecture — Shopify Engineering](https://shopify.engineering/react-native-new-architecture) — MEDIUM confidence (large-scale practitioner post)
- [Upgrading React Native 0.74.3 to 0.79.5 — DEV Community](https://dev.to/kigbu/upgrading-react-native-from-0743-to-0795-a-journey-through-common-pitfalls-and-solutions-4jnn) — MEDIUM confidence (practitioner post-mortem)
- [React Native Minimum Gradle Version Issue #46047](https://github.com/facebook/react-native/issues/46047) — HIGH confidence (official issue tracker)
- [App Router Pitfalls — imidef.com](https://imidef.com/en/2026-02-11-app-router-pitfalls) — LOW confidence (single source, unverified)
- [Vitest Adoption Guide — LogRocket](https://blog.logrocket.com/vitest-adoption-guide/) — MEDIUM confidence (verified against official docs)

---
*Pitfalls research for: JS Upgrade Agents (Next.js, CRA→Vite, Vite+React, React Native)*
*Researched: 2026-03-01*
