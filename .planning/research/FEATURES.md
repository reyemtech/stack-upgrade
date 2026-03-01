# Feature Research

**Domain:** Autonomous JS upgrade/migration agents (Next.js, CRA→Vite, Vite+React, React Native)
**Researched:** 2026-03-01
**Confidence:** MEDIUM-HIGH (official docs verified, supplemented with WebSearch findings)

---

## Feature Landscape

This document covers features across four JS upgrade agent types. Each section notes which agents the feature applies to:

- **[NX]** — Next.js upgrade agent
- **[CV]** — CRA→Vite migration agent
- **[VR]** — Vite+React upgrade agent
- **[RN]** — React Native upgrade agent

---

### Table Stakes (Users Expect These)

Features whose absence makes the agent useless. These are the baseline — not having them means the agent produces broken or unusable output.

| Feature | Agents | Why Expected | Complexity | Notes |
|---------|--------|--------------|------------|-------|
| Package.json dependency version bumps | NX, CV, VR, RN | Core of any upgrade | LOW | npm/yarn update, version constraint changes |
| Official codemod execution | NX | Next.js provides `@next/codemod` — users expect it to be run | LOW | `npx @next/codemod@latest upgrade` handles async APIs, middleware→proxy rename automatically. Confidence: HIGH (official docs) |
| Middleware→proxy file rename | NX | Breaking change in Next.js 16 — app won't build without it | LOW | Rename middleware.ts/js → proxy.ts/js; update nextConfig references. Covered by official codemod. |
| Async Request API migration | NX | cookies(), headers(), draftMode() are now async in Next.js 15+; sync access removed in 16 | MEDIUM | Codemod handles most cases; edge cases (dynamic access patterns) need agent reasoning |
| Turbopack config migration | NX | experimental.turbopack moved to top-level in Next.js 16; webpack custom configs need --webpack flag | MEDIUM | Agent must detect custom webpack config and advise/convert |
| env var prefix rewrite (REACT_APP_ → VITE_) | CV | CRA uses REACT_APP_, Vite uses VITE_. Code breaks silently if not migrated. | MEDIUM | Requires file-wide search-replace in .env files AND all source files (process.env.REACT_APP_ → import.meta.env.VITE_). Confidence: HIGH (multiple verified sources) |
| index.html move from public/ to project root | CV | Vite requires index.html at root — CRA puts it in public/ | LOW | Simple file move + script tag update to inject entry point |
| vite.config.js generation | CV | No vite.config means no dev server, no build | LOW | Generate from scratch with @vitejs/plugin-react |
| package.json scripts rewrite | CV | react-scripts commands → vite/vitest equivalents | LOW | start→vite, build→vite build, test→vitest |
| react-scripts removal | CV | Leaves dead dep if not removed | LOW | Remove from dependencies after migration |
| .js → .jsx rename for JSX files | CV | Vite is explicit about JSX in .js files; CRA was permissive | MEDIUM | Detect files with JSX content, rename — tricky when imports reference them (must update all import paths) |
| React peer dependency upgrade | VR | React 19 has breaking changes; useRef now requires argument; JSX namespace changes | MEDIUM | Must update @types/react, react-dom simultaneously. Confidence: HIGH (React 19 release notes) |
| Vite plugin updates | VR | @vitejs/plugin-react may need major bump; plugin APIs change between Vite majors | LOW | Also handle vite-plugin-svgr, vite-plugin-pwa etc. if present |
| Node.js minimum version enforcement | VR | Vite 6 dropped Node 18 support; requires Node 20.19+ or 22.12+ | LOW | Detect from .nvmrc, .node-version, engines field; flag if container Node version is insufficient |
| React Native version bump | RN | Core of the upgrade | LOW | Update react-native in package.json with exact pegged version |
| Upgrade Helper diff application | RN | The official RN Upgrade Helper (react-native-community/upgrade-helper) provides file-by-file diffs between versions — this is the authoritative migration source | HIGH | Agent must fetch or embed the diff for the target version pair and apply it to android/, ios/ template files. Confidence: HIGH (official RN docs) |
| Gradle wrapper version update | RN | Mismatched Gradle wrapper causes build failures | MEDIUM | Update gradle-wrapper.properties distributionUrl. Each RN version pins a specific Gradle version. |
| settings.gradle autolinking migration | RN | native_modules.gradle removed; autolinkLibrariesWithApp is the replacement | MEDIUM | Required from RN 0.71+. Confidence: HIGH (RN Gradle plugin docs) |
| Podfile iOS deployment target update | RN | RN raises minimum iOS deployment target with each major | LOW | Update platform :ios, 'X.X' in ios/Podfile |
| pod install execution | RN | iOS native deps are linked via CocoaPods; must run after package changes | LOW | Run `pod install` in ios/ directory. Will fail in Linux-only Docker (iOS verification impossible without macOS) |
| New Architecture enablement | RN | RN 0.82+ runs entirely on New Architecture; old arch frozen as of June 2025 | HIGH | Set newArchEnabled=true in android/gradle.properties and ios/Podfile. Third-party native modules must be New Arch compatible — this is the primary risk. Confidence: HIGH (RN 0.82 release notes) |
| npm/yarn audit after upgrade | NX, CV, VR, RN | Security is a baseline expectation | LOW | Flag high-severity vulns in run-log, don't block on audit failures |
| Build verification | NX, CV, VR, RN | Agent must prove the build succeeds | MEDIUM | next build / vite build / react-native run-android equivalent |
| Test suite run | NX, CV, VR, RN | Agent must not break existing tests | MEDIUM | Jest / Vitest / RN Jest runner |
| One-commit-per-phase + PR creation | NX, CV, VR, RN | Same quality bar as Laravel agent | LOW | Matches existing monorepo pattern |
| Recon before action | NX, CV, VR, RN | Prerequisite for safe upgrades — must know what's in the repo | MEDIUM | JS recon: parse package.json, detect framework version, identify which router/arch variant, list third-party native modules (RN) |
| Unused package removal | NX, CV, VR, RN | Same principle as Laravel agent — don't upgrade dead code | MEDIUM | Static analysis of imports; safer to flag than auto-remove for JS due to barrel exports and dynamic requires |

---

### Differentiators (Competitive Advantage)

These features are not table stakes but provide significant value over manual upgrades. They are what makes the agent worth using over following a migration guide by hand.

| Feature | Agents | Value Proposition | Complexity | Notes |
|---------|--------|-------------------|------------|-------|
| Pages Router → App Router detection and incremental migration | NX | Pages Router is not deprecated but App Router is the future. Agent detects which router the project uses and offers incremental migration (not forced big-bang). | HIGH | Full Pages→App migration is a weeks-long effort for large apps (100k+ LOC took >1 week per verified source). Agent should do a per-route incremental migration or clearly scope what it migrates. Do NOT attempt full automatic RSC conversion — too high risk of behaviour change. |
| RSC 'use client' boundary insertion | NX | After App Router migration, components using hooks/context/browser APIs need 'use client' directive. Agent can detect these and insert directives. | HIGH | Requires AST analysis — detecting useState, useEffect, context consumers, event handlers. Missing a boundary causes runtime errors. This is the most common App Router migration error. |
| vite.config.js proxy translation from CRA setupProxy.js | CV | CRA uses http-proxy-middleware in src/setupProxy.js; Vite uses server.proxy in vite.config.js. Format is different. | MEDIUM | Agent translates proxy rules rather than leaving them broken/missing. Common in enterprise CRA apps hitting backend APIs. |
| Jest → Vitest migration | CV, VR | Vitest is the natural test runner for Vite projects; most Jest tests work with minimal changes. Agent migrates jest.config.js → vitest.config.ts, updates jest.fn() → vi.fn() etc. | MEDIUM | Migration is mechanical but tedious manually. Key difference: Vitest async behavior differs from Jest in some edge cases. Should be optional — some teams prefer to keep Jest with babel-jest. |
| SVG import plugin detection and setup | CV, VR | Vite doesn't handle `import Logo from './logo.svg'` as a React component out of the box — CRA did via SVGR. Agent detects SVG-as-component usage and installs vite-plugin-svgr automatically. | LOW | Very common in CRA→Vite migrations; very easy to miss; breaks silently at runtime. |
| Third-party library New Architecture compatibility audit | RN | New Arch is now default (RN 0.82+). Agent audits all native modules for TurboModules/Fabric compatibility and flags incompatible ones with remediation options (update/replace/disable). | HIGH | This is the #1 blocker for RN upgrades in 2025. Shopify, Callstack confirmed this is the dominant risk. Requires knowledge of which versions of popular libraries (react-navigation, react-native-screens, etc.) support New Arch. |
| AppDelegate / MainApplication migration (Kotlin) | RN | RN now recommends Kotlin for Android native code (MainApplication.kt). Java MainApplication.java still works but is deprecated pattern. Agent migrates Java → Kotlin. | HIGH | Only do this if the project is already mixed Kotlin/Java or on request. Auto-migration risks introducing Kotlin compilation errors in modules that haven't been updated. Flag as recommendation rather than auto-apply. |
| Google Play API level 35 compliance | RN | Google Play requires targetSdkVersion 35 as of 2025. Agent updates build.gradle accordingly and identifies libraries that break with API 35. | MEDIUM | This is often the forcing function for RN upgrades in production apps. Confidence: MEDIUM (WebSearch verified, not official RN docs) |
| Next.js cache semantic change notification | NX | Next.js 15 changed default caching from opt-out to opt-in for fetch() and Route Handlers. Silent behaviour change — apps may start seeing stale or fresh data unexpectedly. Agent identifies fetch() calls and GET Route Handlers and adds explicit cache directives. | HIGH | Cannot be automated safely — requires understanding of intent. Agent should enumerate affected locations and log them for human review. |
| Changelog and per-phase run-log | NX, CV, VR, RN | Same durable memory pattern as Laravel agent. Each phase logged, changelog becomes PR body. | LOW | Directly reuses playbook pattern from Laravel agent. High value vs manual upgrade where nothing is documented. |
| TypeScript type breaking change fixups | NX, VR | React 19 changed several TypeScript types (useRef, JSX namespace). Agent detects and fixes TS compilation errors caused by type changes. | MEDIUM | Requires running tsc --noEmit and parsing output. Much faster than manual TS error triage. |
| Dependency snapshot before/after | NX, CV, VR, RN | Same as Laravel agent — JSON snapshots of package.json deps before and after for diff-based review | LOW | Direct port from Laravel agent. Useful for PR reviewers. |
| Brownfield / non-standard project structure handling | RN | RN apps often have non-standard directory layouts (monorepo, custom android/ structure). Agent should detect these and adapt rather than hard-failing. | HIGH | Lowest confidence — complex to implement; flag as v2+ feature. Confidence: LOW |

---

### Anti-Features (Deliberately Not Build)

Features that seem useful but should be explicitly avoided.

| Anti-Feature | Why Requested | Why Problematic | Alternative |
|--------------|---------------|-----------------|-------------|
| Full automatic Pages Router → App Router conversion | Seems like a natural goal for a Next.js agent | Pages→App is NOT a mechanical refactor. RSC requires understanding data-fetching intent, context usage, auth patterns, third-party library compatibility. Automated conversion has high risk of silent behavior changes. One production migration of 100k LOC took a team over 1 week manually. | Agent detects router type, runs version upgrade codemods, and documents what remains for manual App Router migration. Scope App Router migration as a separate, opt-in agent mode (v2+). |
| iOS Simulator build verification in CI | Proves the iOS build works | Requires macOS + Xcode. Linux Docker containers cannot run Xcode. Building iOS in Docker is not feasible without macOS runners. | Agent runs `pod install`, validates Podfile syntax, reports success/failure of native step. Full iOS build verification deferred to human on macOS. Kubernetes job on macOS runner is possible future work (v2+). |
| Automatic NewArch native module rewriting | Wants zero-effort New Arch migration | Rewriting native modules from Old Arch (bridge) to TurboModules/Fabric requires understanding the C++/Java/ObjC bridge layer — not safe to automate. High risk of breaking native functionality silently. | Agent audits compatibility, flags incompatible modules, links to official migration guide. Human rewrites native modules. |
| Jest config auto-migration to Vitest during CRA→Vite | Seems like a one-step migration | Jest→Vitest migration has subtle async semantic differences. Doing it at the same time as CRA→Vite doubles complexity and makes failures harder to attribute. | Migrate build tooling first (CRA→Vite), verify build passes and Jest still runs via babel-jest, then offer Vitest migration as a separate optional phase. |
| Monorepo (Turborepo/Nx) support | Most large companies use monorepos | Workspace detection, shared package resolution, and per-package upgrade targeting are a different problem class. Out of scope per PROJECT.md. | v1 assumes single-package repos. Detect monorepo signals (turbo.json, nx.json, workspaces in package.json) and fail fast with a clear error message. |
| Expo support | Large part of the RN ecosystem | Expo has its own upgrade CLI (`expo upgrade`) and SDK versioning that doesn't map to bare RN workflows. Separate problem domain. Explicitly out of scope per PROJECT.md. | Detect Expo projects (expo field in package.json, app.json with expo field) and fail fast with a clear error message pointing to Expo's own tooling. |
| Fully autonomous multi-version skip (e.g., 0.70 → 0.82) | Users on very old versions want a big jump | Multi-major RN upgrades have compounding breaking changes. Each minor version may require native file changes that the next version's diff assumes are already applied. Skipping versions produces wrong diffs. | Agent upgrades one major at a time (or one minor at a time for RN). For large version gaps, queue multiple sequential upgrade runs. Document this constraint clearly. |

---

## Feature Dependencies

```
[Recon / package.json analysis]
    └──required by──> [Stack-type detection]
                          └──required by──> [Template selection]
                          └──required by──> [Phase ordering]

[Official codemod execution] (NX)
    └──should precede──> [Manual breaking change fixes]
    └──covers──> [Middleware→proxy rename]
    └──covers──> [Async Request API migration]

[Vite config generation] (CV)
    └──required before──> [env var prefix rewrite]
    └──required before──> [index.html move]
    └──required before──> [proxy translation]

[Build verification]
    └──required before──> [Phase marked complete]
    └──required before──> [PR creation]

[React Native version bump] (RN)
    └──required before──> [Upgrade Helper diff application]
    └──required before──> [Gradle wrapper update]
    └──required before──> [pod install]

[New Architecture enablement] (RN)
    └──requires──> [Third-party library New Arch audit]
                       └──must complete before──> [New Arch flag set to true]

[Pages Router detection] (NX)
    └──gates──> [App Router migration scope decision]

[Jest→Vitest migration] (CV, VR)
    └──should be separate phase from──> [Build tooling migration]
    └──optional / not blocking──> [Build verification]
```

### Dependency Notes

- **Recon required by all phases:** JS recon must parse package.json, detect framework version, identify router/arch variant, and enumerate native modules (RN) before any upgrade phase starts.
- **Codemod precedes manual fixes (NX):** Running @next/codemod first reduces the manual work surface. Running it after manual changes risks conflicts.
- **New Arch audit gates New Arch flag (RN):** Enabling New Architecture before auditing library compatibility will cause runtime crashes for apps with incompatible native modules. Audit first, enable second.
- **CRA build tooling migration is separate from test runner migration (CV):** Conflating these causes failures that are hard to attribute. Verify build passes with Jest still running via babel-jest before attempting Vitest migration.

---

## MVP Definition

### Launch With (v1)

Minimum viable — agent produces a working upgraded repo that builds and passes tests.

- [ ] **All table stakes features** for each stack — version bumps, codemods, config migrations, build verification
- [ ] **Recon before action** — JS-specific recon script (package.json analysis, framework detection, native module listing for RN)
- [ ] **Stack-specific verify-fast.sh and verify-full.sh** — npm run build + test suite for web stacks; Gradle build check for RN
- [ ] **Upgrade Helper diff application (RN)** — authoritative source for native file changes
- [ ] **New Arch library audit (RN)** — non-negotiable given RN 0.82 defaults to New Arch
- [ ] **SVG import plugin detection (CV, VR)** — too commonly broken to defer; very low complexity
- [ ] **Changelog + run-log + PR creation** — playbook compliance; reuse from Laravel agent

### Add After Validation (v1.x)

- [ ] **Jest → Vitest migration (CV, VR)** — add as optional phase once core migration is proven stable
- [ ] **TypeScript type fixups (NX, VR)** — add when TypeScript projects are common in test corpus
- [ ] **Google Play API level 35 compliance (RN)** — add once tested against real production RN apps
- [ ] **'use client' boundary insertion (NX)** — add once App Router migration scoping is defined

### Future Consideration (v2+)

- [ ] **Pages Router → App Router migration (NX)** — requires dedicated scope, separate agent mode, significant complexity
- [ ] **AppDelegate/MainApplication Kotlin migration (RN)** — opt-in only; high risk without testing on real projects
- [ ] **Brownfield / monorepo support (RN)** — different problem class; wait for user demand signal
- [ ] **iOS build verification on macOS runners** — requires Kubernetes macOS runner setup; infrastructure investment

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Package version bumps + codemods (NX, CV, VR, RN) | HIGH | LOW | P1 |
| Env var prefix rewrite REACT_APP_→VITE_ (CV) | HIGH | LOW | P1 |
| Vite config generation (CV) | HIGH | LOW | P1 |
| Upgrade Helper diff application (RN) | HIGH | MEDIUM | P1 |
| New Arch library audit (RN) | HIGH | HIGH | P1 |
| Build verification all stacks | HIGH | MEDIUM | P1 |
| Recon script (JS) | HIGH | MEDIUM | P1 |
| SVG import plugin detection (CV, VR) | MEDIUM | LOW | P1 |
| Gradle/Podfile/settings.gradle updates (RN) | HIGH | MEDIUM | P1 |
| index.html move + scripts rewrite (CV) | HIGH | LOW | P1 |
| Changelog + run-log + PR (all) | MEDIUM | LOW | P1 |
| TypeScript type fixups (NX, VR) | MEDIUM | MEDIUM | P2 |
| Jest → Vitest migration (CV, VR) | MEDIUM | MEDIUM | P2 |
| Proxy config translation (CV) | MEDIUM | MEDIUM | P2 |
| Cache semantic change notification (NX) | MEDIUM | MEDIUM | P2 |
| Google Play API 35 compliance (RN) | HIGH | MEDIUM | P2 |
| 'use client' boundary insertion (NX) | HIGH | HIGH | P2 |
| Pages Router → App Router migration (NX) | HIGH | VERY HIGH | P3 |
| Kotlin migration (RN) | LOW | HIGH | P3 |
| Brownfield support (RN) | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for launch (v1)
- P2: Should have, add after validation (v1.x)
- P3: Nice to have, future consideration (v2+)

---

## Competitor / Reference Analysis

| Feature | Manual upgrade (following docs) | existing JS migration tools (viject, @next/codemod) | This agent |
|---------|--------------------------------|-----------------------------------------------------|------------|
| Package version bumps | Manual + npm | Partial automation | Automated + verified |
| Codemod execution | User must know to run it | Built-in | Automated |
| Build verification | Manual | None | Automated in verify-fast.sh |
| Test run | Manual | None | Automated |
| Native file diffs (RN) | Upgrade Helper web UI, applied manually | None | Automated diff application |
| PR creation | Manual | None | Automated with changelog |
| Run log / audit trail | None | None | Three-file memory system |
| Restart resilience (ralph loop) | N/A | N/A | Built-in |
| New Arch library audit (RN) | Manual research per library | None | Automated audit |
| 'use client' boundary detection (NX) | Manual code review | None | Automated AST detection (v1.x) |

---

## Sources

- [Next.js Upgrading Guide](https://nextjs.org/docs/app/guides/upgrading) — official, HIGH confidence
- [Next.js Version 16 Upgrade Guide](https://nextjs.org/docs/app/guides/upgrading/version-16) — official, HIGH confidence
- [Next.js Codemods](https://nextjs.org/docs/app/guides/upgrading/codemods) — official, HIGH confidence
- [Next.js Middleware→Proxy rename](https://nextjs.org/docs/messages/middleware-to-proxy) — official, HIGH confidence
- [React.dev: Sunsetting Create React App](https://react.dev/blog/2025/02/14/sunsetting-create-react-app) — official React team, HIGH confidence
- [Vite Migration from v6](https://vite.dev/guide/migration) — official Vite docs, HIGH confidence
- [Vite 7.0 release](https://vite.dev/blog/announcing-vite7) — official, HIGH confidence
- [React v19 release notes](https://react.dev/blog/2024/12/05/react-19) — official, HIGH confidence
- [React Native Upgrading guide](https://reactnative.dev/docs/upgrading) — official, HIGH confidence
- [React Native 0.82 release](https://reactnative.dev/blog/2025/10/08/react-native-0.82) — official, HIGH confidence
- [React Native Gradle Plugin docs](https://reactnative.dev/docs/react-native-gradle-plugin) — official, HIGH confidence
- [react-native-community/upgrade-helper](https://github.com/react-native-community/upgrade-helper) — official community tool, HIGH confidence
- [Shopify: Migrating to React Native's New Architecture](https://shopify.engineering/react-native-new-architecture) — production case study, MEDIUM confidence
- [Callstack: How to Upgrade React Native in a Brownfield App](https://www.callstack.com/blog/how-to-upgrade-react-native-in-a-brownfield-application) — expert source, MEDIUM confidence
- [viject: CRA to Vite automated migration tool](https://github.com/bhbs/viject) — community tool, MEDIUM confidence
- [FreeCodeCamp: Migrate CRA to Vite using Jest and Browserslist](https://www.freecodecamp.org/news/how-to-migrate-from-create-react-app-to-vite/) — MEDIUM confidence
- [Next.js App Router migration: the good, bad, and ugly](https://www.flightcontrol.dev/blog/nextjs-app-router-migration-the-good-bad-and-ugly) — production case study, MEDIUM confidence

---
*Feature research for: JS upgrade agents (Next.js, CRA→Vite, Vite+React, React Native)*
*Researched: 2026-03-01*
