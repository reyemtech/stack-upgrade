# Project Research Summary

**Project:** stack-upgrade — JS upgrade/migration agents
**Domain:** Autonomous code upgrade agents running inside Docker containers (Next.js, CRA→Vite, Vite+React, React Native)
**Researched:** 2026-03-01
**Confidence:** MEDIUM-HIGH

## Executive Summary

This project extends the existing Laravel upgrade agent monorepo with four new JS upgrade/migration targets: Next.js major version upgrades, CRA→Vite migrations, Vite+React version bumps, and React Native bare workflow upgrades. All four follow the same foundational playbook (Three-File Memory System, ralph-loop, recon-before-action, one-commit-per-phase) but differ significantly in tooling, image weight, and risk profile. The recommended architecture consolidates the three web JS stacks (Next.js, CRA, Vite+React) into a single lean `stacks/node/` Docker image with per-stack template subdirectories, while React Native lives in a separate `stacks/react-native/` image due to its Android SDK (~2GB) requirements.

The upgrade tooling is mature and official for the highest-value stacks: `@next/codemod upgrade` handles Next.js codemods automatically; `react-native upgrade` + `@rnx-kit/align-deps` handles RN native alignment; `viject` handles CRA→Vite structural migration. Vite+React is the most manual of the four (no single codemod exists — it is pure package bumps + React 19 codemods). The three web JS stacks share identical system dependencies, verify scripts, and the ralph-loop pattern, enabling a single Dockerfile and shared scripts directory. This is the primary architectural efficiency to capture.

The dominant risks are stack-specific and non-obvious at build time: Next.js async dynamic APIs that the codemod marks but does not resolve (silently broken at runtime), CRA→Vite environment variable prefix migration that builds successfully but fails in production (process.env.REACT_APP_* becomes undefined), and React Native New Architecture library incompatibility that crashes at app launch even when the build succeeds. All three of these pitfalls share a pattern: the build passes, tests pass, but the app is broken at runtime. Verification strategies must be designed around this gap — specifically, post-build grep checks for known failure signatures, not just exit-code-based test runs.

## Key Findings

### Recommended Stack

The web JS stacks (Next.js, CRA→Vite, Vite+React) all run from a single `node:22-bookworm-slim` base image (~200MB compressed). Node 22 is Active LTS through 2027 and satisfies Vite 7.x's minimum requirement of Node 20.19+ or 22.12+. Alpine is explicitly ruled out — musl libc causes silent failures with native npm packages common in real-world repos. React Native requires a separate image built on the same Node 22 base but with OpenJDK 17 (`openjdk-17-jdk-headless`) and Android SDK 36/NDK 27 added, targeting ~2GB. JDK 21 is explicitly ruled out — it causes Gradle/Kotlin incompatibilities with RN 0.84 as of March 2026.

**Core technologies:**
- `node:22-bookworm-slim`: Web JS agent base — Active LTS, slim, Bookworm Debian supported through ~2028, consistent with Laravel stack
- `@next/codemod upgrade`: Next.js upgrade automation — official Vercel tool, handles package bump + codemod selection atomically
- `viject`: CRA→Vite migration — removes react-scripts, generates vite.config.ts, rewrites package.json scripts (MEDIUM confidence — active but small community)
- `react-codemod` + `types-react-codemod`: React 18→19 API migration — official React team tooling, required for any stack touching React 19
- `react-native upgrade` CLI: RN native file updates — official, uses rn-diff-purge internally
- `@rnx-kit/align-deps`: RN ecosystem dependency alignment — Microsoft-maintained, resolves peer dep hell for native modules
- `@anthropic-ai/claude-code`: Agent runtime — same as Laravel stack, latest version
- `gh` CLI, `jq`, `gettext-base`, `git`, `ssh-client`, `curl`: Shared operational dependencies across all images

### Expected Features

**Must have (table stakes — v1):**
- Package version bumps (all stacks) — core of any upgrade
- `@next/codemod upgrade` execution (NX) — official tool, users expect it to run
- Middleware→proxy rename + async Request API migration (NX) — Next.js 16 breaking changes; app will not build without them
- env var prefix rewrite `REACT_APP_*` → `VITE_*` in both `.env` files and source code (CV) — silently breaks at runtime otherwise
- Vite config generation, index.html restructure, package.json scripts rewrite (CV) — structural migration requirements
- Gradle/AGP version update, settings.gradle autolinking migration, Podfile iOS target update (RN) — native build files, not managed by npm
- New Architecture pre-upgrade library compatibility audit (RN) — RN 0.82+ has New Arch permanently enabled; incompatible libraries crash at launch
- Upgrade Helper diff application for native Android/iOS files (RN) — authoritative source for native file changes per version pair
- Build verification for all stacks (npm run build / next build / gradlew assembleDebug)
- JS recon script: package.json analysis, stack detection, TypeScript detection, test runner detection, native module enumeration (RN)
- Changelog + run-log + PR creation (all stacks) — playbook compliance, reuses Laravel pattern

**Should have (differentiators — v1.x):**
- SVG-as-component detection and `vite-plugin-svgr` installation (CV, VR) — very common CRA pattern that breaks silently after migration; low complexity
- Jest→Vitest migration as a separate optional phase (CV, VR) — adds value but must not block build verification
- TypeScript type breaking change fixups: `tsc --noEmit` + error parsing (NX, VR) — React 19 changed useRef, JSX namespace
- CRA proxy translation from `setupProxy.js` → `vite.config.ts` `server.proxy` (CV) — common in enterprise CRA apps
- Next.js fetch cache semantic change notification (NX) — v15 flipped default from force-cache to no-store; silent behavior change
- Google Play API level 35 compliance check (RN) — common forcing function for RN upgrades in production apps

**Defer (v2+):**
- Pages Router → App Router full migration (NX) — weeks-long effort for large apps, requires understanding data-fetching intent, cannot be automated safely
- AppDelegate/MainApplication Kotlin migration (RN) — opt-in only, high risk without testing on real projects
- Brownfield/monorepo support (RN, all stacks) — different problem class, requires workspace detection and per-package targeting
- iOS build verification on macOS runners — requires Kubernetes macOS runner, infrastructure investment
- Expo support — separate problem domain, explicit out-of-scope per PROJECT.md

**Anti-features (explicitly do not build):**
- Full automatic Pages→App Router conversion — RSC conversion requires understanding intent; automated conversion produces silent behavior changes
- `npm install --legacy-peer-deps` as default — masks real peer dep conflicts; only as logged last resort
- iOS Simulator build in Linux Docker — macOS toolchain requirement makes this impossible

### Architecture Approach

The monorepo adds two new stack directories: `stacks/node/` (single Dockerfile serving Next.js, CRA→Vite, and Vite+React via per-stack template subdirectories) and `stacks/react-native/` (separate heavy image with Android SDK). The node entrypoint introduces one new capability vs the Laravel entrypoint: auto-detection of stack type from `package.json` after clone, selecting the correct template subdirectory (`nextjs/`, `cra/`, or `vite-react/`). Everything else — Three-File Memory System, ralph-loop, recon→baseline→ralph execution flow, output artifacts, CLI integration pattern — is identical to the Laravel agent.

**Major components:**
1. `stacks/node/Dockerfile` — lean ~500MB web JS image: Node 22, gh CLI, Claude Code, envsubst, jq, git, ssh-client
2. `stacks/node/entrypoint.sh` — clone → detect stack type → select templates → npm ci → before-snapshots → baseline verify → recon → ralph; detection logic uses `jq` on package.json with priority: next > react-scripts (CRA) > vite+react
3. `stacks/node/templates/{nextjs,cra,vite-react}/` — per-stack CLAUDE.md, plan.md, checklist.yaml (run-log.md and changelog.md templates are shared)
4. `stacks/node/scripts/recon.sh` — JS-specific: detects framework version, TypeScript presence, test runner (Jest/Vitest), CSS tooling, build output, import patterns
5. `stacks/node/scripts/verify-fast.sh` — TypeScript type check + lint + unit tests (seconds); `verify-full.sh` adds npm run build + audit
6. `stacks/node/scripts/ralph-loop.sh` — identical pattern to Laravel: restart on incomplete checklist, write status.json/result.json, push + PR on completion
7. `stacks/react-native/` — separate directory, separate Dockerfile (~2GB), RN-specific recon (Gradle version, native module enumeration), conditional Android build in verify-full.sh behind `ANDROID_BUILD=true`
8. `cli/src/stacks.js` — add four new entries: nextjs, cra, vite-react, react-native; each with detection function (reads package.json), Docker image name, env key, branch prefix

### Critical Pitfalls

1. **RSC boundary violations propagate upward silently (Next.js App Router)** — Agent adds `"use client"` to a component, then to its parent because it imports that component, eventually marking the entire app as client-only. App builds successfully but produces zero RSC payloads, defeating the purpose of App Router migration. Prevention: add `"use client"` only at the lowest boundary that needs it; verify RSC payloads exist in Network tab (`text/x-component`). This is a v2+ concern (App Router migration is deferred), but must be documented in templates for Next.js upgrade work.

2. **CRA→Vite env var migration is incomplete without CI pipeline changes** — Renaming `REACT_APP_*` to `VITE_*` in `.env` files and source code is necessary but not sufficient. CI/CD pipeline secrets (GitHub Actions, Vercel, Netlify) still have the old names and will cause silent `undefined` at runtime. Prevention: recon enumerates all `process.env.REACT_APP_` references; post-build grep of `dist/` for `process.env.REACT_APP_` catches incomplete migration; template CLAUDE.md must explicitly instruct the agent to document the CI pipeline variables that need external renaming.

3. **Next.js async dynamic APIs: codemod marks but does not resolve edge cases** — `@next/codemod` inserts `UnsafeUnwrapped` TypeScript casts and `@next/codemod` comments where it cannot automatically resolve async patterns. Agent must search for these markers after codemod runs and treat each as a required manual fix. Prevention: add `grep -r "UnsafeUnwrapped\|@next/codemod" src/` to verify-fast.sh as a blocking check.

4. **React Native New Architecture library compatibility must be audited before version bump** — RN 0.82+ has New Arch permanently enabled. Libraries with old Bridge bindings that haven't migrated to TurboModules crash at app launch even when the build succeeds. Recovery is HIGH cost (find alternative library, or fork). Prevention: recon audits native modules against React Native Directory before any version change; this check is Phase 0, not Phase 1.

5. **Gradle/AGP version mismatch causes Android build failure (React Native)** — Gradle wrapper and Android Gradle Plugin versions are version-locked per RN release and are NOT managed by npm. An agent that only bumps `package.json` and runs `npm install` will miss these native build file updates. Prevention: recon extracts current AGP and Gradle wrapper versions; after RN bump, Upgrade Helper diff provides correct target versions; verify-fast.sh for RN includes `./gradlew --version` check.

## Implications for Roadmap

Based on research, suggested phase structure (9 phases):

### Phase 1: Shared Node Image Foundation
**Rationale:** The Dockerfile, entrypoint, and shared scripts are the foundation everything else depends on. Must exist and be testable before any template work is useful. Next.js is the highest-value stack — validates shared script assumptions first.
**Delivers:** `stacks/node/Dockerfile` (~500MB), `stacks/node/entrypoint.sh` with auto-detection logic, `stacks/node/scripts/` (recon.sh, verify-fast.sh, verify-full.sh, ralph-loop.sh, stream-pretty.sh)
**Addresses:** Auto-detection pattern (jq-based package.json parsing), STACK_TYPE env override, branch naming (upgrade/nextjs-{version}), before-snapshots, baseline verify, recon, template substitution
**Avoids:** One-image-per-web-JS-stack anti-pattern (bloats CI, duplicates Dockerfiles); detection-in-CLI anti-pattern (CLI does best-effort hint, entrypoint re-detects authoritatively)

### Phase 2: Next.js Agent Templates
**Rationale:** Next.js is the most common upgrade case and validates the shared script assumptions. Build templates before wiring CLI — templates need to work end-to-end before being exposed in the CLI registry.
**Delivers:** `stacks/node/templates/nextjs/` — CLAUDE.md (upgrade instructions), plan.md (6-phase upgrade plan), checklist.yaml (phase tracking)
**Implements:** Template variable substitution with `TARGET_NEXTJS`, `UPGRADE_DATE`, `STACK_TYPE`; phase structure: Recon → Core Framework + Codemod → First-Party Packages → Third-Party Packages → Frontend Build → Config/README → Verification
**Avoids:** Async dynamic API markers left in source (add UnsafeUnwrapped grep to verify-fast.sh); caching semantics inversion (explicit cache opts as part of Phase 1 tasks); middleware testing deferred (middleware explicitly addressed in phase tasks, not assumed covered by unit tests)

### Phase 3: CRA→Vite Migration Agent Templates
**Rationale:** CRA migration is structurally different from an upgrade (one-way, migration not version bump, branch prefix is `migrate/cra-to-vite` not `upgrade/cra-{version}`). Build after Next.js templates to confirm the shared scripts work correctly with a structurally different workflow.
**Delivers:** `stacks/node/templates/cra/` — CLAUDE.md (migration instructions), plan.md (migration plan), checklist.yaml; `viject` as primary tool + manual fallback documented in CLAUDE.md
**Implements:** env var migration (REACT_APP_* → VITE_*), index.html restructure, vite.config.ts generation, package.json scripts rewrite, SVG-as-component detection and vite-plugin-svgr installation, proxy config translation
**Avoids:** env var migration incomplete (post-build grep check for process.env.REACT_APP_ in dist/); Jest→Vitest conflation (separate optional phase, does not block build verification)

### Phase 4: Vite+React Upgrade Agent Templates
**Rationale:** Simplest of the three web JS stacks — pure package bumps + React 19 codemods. Build last of the web stacks because it validates the template selection logic works for all three paths.
**Delivers:** `stacks/node/templates/vite-react/` — CLAUDE.md (upgrade instructions), plan.md (Vite + React version bump plan), checklist.yaml
**Implements:** Vite major bump (npm install vite@latest @vitejs/plugin-react@latest), React 18→19 migration (react-codemod + types-react-codemod), Vitest upgrade if present, plugin compatibility verification (deprecation warning grep in vite build output)
**Avoids:** Plugin incompatibility post-bump (treat vite build deprecation warnings as blocking failures); Fast Refresh not verified (include dev server HMR check)

### Phase 5: CLI Registry Integration (Web Stacks)
**Rationale:** Wire up the three web JS stacks in the CLI after all three image/template combinations are testable end-to-end. CLI registry is best validated against working images.
**Delivers:** `cli/src/stacks.js` entries for nextjs, cra, vite-react — each with package.json detection function, image name (`ghcr.io/reyemtech/node-upgrade-agent`), env key (TARGET_NEXTJS / — / TARGET_VITE), branch prefix; `cli/src/github.js` updated to detect JS stacks from package.json
**Implements:** Best-effort detection in CLI (UX feedback to user), STACK_TYPE passed as overridable hint, not authoritative detection

### Phase 6: React Native Image and Templates
**Rationale:** React Native is a separate image (heavy, slow CI build) and separate problem domain. Build last of the stacks because the pattern is proven by then and CI matrix additions are straightforward. The image takes 10+ minutes to build — building it before the pattern is stable wastes time.
**Delivers:** `stacks/react-native/Dockerfile` (~2GB, Node 22 + JDK 17 + Android SDK 36 + NDK 27), `stacks/react-native/entrypoint.sh`, `stacks/react-native/scripts/` (RN-specific recon, verify-fast, verify-full with `ANDROID_BUILD=true` gate, ralph-loop), `stacks/react-native/templates/react-native/` (CLAUDE.md, plan.md, checklist.yaml)
**Addresses:** Pre-upgrade New Arch library audit (Phase 0 in agent plan — must complete before version bump); Gradle/AGP version update; Upgrade Helper diff application for native files; `pod deintegrate && pod install` (not just pod install) for iOS; `./gradlew clean` before Android build
**Avoids:** Android builds by default (gate behind ANDROID_BUILD=true — 10-30 min build that blocks all verification); New Arch incompatible library crash (audit before any npm version changes)

### Phase 7: CLI Registry Integration (React Native)
**Rationale:** Wire up React Native in CLI after the RN image and templates are testable. Separate phase from web stacks because RN has a distinct detection logic (react-native dependency in package.json + android/ and ios/ directories present + no expo field).
**Delivers:** `cli/src/stacks.js` entry for react-native — detection function (react-native dep + bare workflow directories), image name (`ghcr.io/reyemtech/react-native-upgrade-agent`), env key (TARGET_RN), branch prefix (`upgrade/react-native-{version}`)

### Phase 8: CI/CD Matrix Expansion
**Rationale:** Add new stacks to CI matrix after all images and CLI entries are working. Adding CI before the images are stable causes unnecessary build failures and wastes CI minutes.
**Delivers:** `.github/workflows/release.yml` matrix entries for `node` and `react-native` stacks; npm publish updated to include new image builds; semantic-release config unchanged
**Implements:** Same multi-arch (amd64 + arm64) Docker build pattern as existing stacks

### Phase 9: End-to-End Validation and Documentation
**Rationale:** Validate all four stacks against real target repos (not just build-succeeds smoke tests). Update README with new stacks, environment variables, and usage examples.
**Delivers:** Validated upgrades against at least one real repo per stack type; README updated with new stacks and CLI usage; CLAUDE.md (project) updated with new stack entries
**Addresses:** Any gaps discovered during real-repo testing; verify-fast.sh and verify-full.sh edge cases; recon script accuracy on real package.json shapes

### Phase Ordering Rationale

- Dockerfile first because all other components depend on a runnable image — testing templates without a working entrypoint is impossible.
- Templates ordered by value and complexity: Next.js (highest value, validates shared scripts) → CRA (different pattern, validates migration vs upgrade) → Vite+React (simplest, validates all three paths work) → CLI wiring → RN (slow image, proven pattern by then).
- CLI registry wired after images are testable — adding CLI entries before images work produces confusing `docker: image not found` errors for users.
- React Native deliberately last — heavy image (slow CI), separate problem domain, pattern is fully established by then, and incompatible library risk is highest (better to discover this on a known-good base).
- CI matrix added after all images are stable — early CI additions fail visibly and waste build minutes.

### Research Flags

Phases likely needing deeper research during planning:

- **Phase 2 (Next.js templates):** The 6-phase upgrade plan structure is not yet defined. Phase ordering within the agent (which codemod runs before which package bump, how to handle middleware without integration tests) needs detailed phase design. Research phase recommended.
- **Phase 3 (CRA templates):** `viject` reliability on diverse CRA project shapes is unverified (MEDIUM confidence). The fallback strategy (manual steps) needs to be scripted clearly enough for the agent to follow without human intervention. Research phase recommended.
- **Phase 6 (React Native image):** Android SDK installation within Docker is well-documented via `react-native-community/docker-android` reference Dockerfile (HIGH confidence), but Gradle cache management, RN Upgrade Helper programmatic access (vs web UI), and `@rnx-kit/align-deps` interaction with lockfiles need detailed investigation. Research phase recommended.

Phases with standard patterns (skip research-phase):

- **Phase 1 (Shared Node Image):** Node 22 + slim Debian + Claude Code is a direct port of the existing Laravel Dockerfile pattern with PHP layer removed. Well-documented, established.
- **Phase 4 (Vite+React templates):** Pure package bumps + React 19 codemods. Official tooling, official migration guides, straightforward.
- **Phase 5 and 7 (CLI registry):** Direct extension of existing `cli/src/stacks.js` pattern. Add entries, done.
- **Phase 8 (CI matrix):** Mechanical extension of existing `.github/workflows/release.yml` matrix. Add stack names, done.
- **Phase 9 (validation):** Not a design problem, an execution problem. No research needed — just real-repo testing.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Next.js, React Native tooling verified against official docs. Vite/React 19 tooling verified. Only gap: `viject` is MEDIUM (active but small community). Version compatibility table verified against official release notes. |
| Features | MEDIUM-HIGH | Table stakes features for all stacks verified against official docs and production case studies. Differentiator features (SVG detection, proxy translation) are well-understood technically. New Arch library audit scope is HIGH confidence from Shopify/Callstack production case studies. |
| Architecture | HIGH | Based on direct analysis of the existing Laravel implementation — the pattern is proven. The new node image architecture (one image, three template subdirectories) is a natural extension. All key decisions are documented in PROJECT.md and confirmed by architecture research. |
| Pitfalls | MEDIUM | Critical pitfalls are well-sourced from official docs and post-mortems. The env var and codemod-marker pitfalls are HIGH confidence. The New Arch library incompatibility pattern is HIGH confidence. RSC boundary propagation is MEDIUM (one practitioner source rated LOW). |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **`viject` reliability on diverse CRA shapes:** viject v1.3.1 has ~175 weekly downloads. It is not battle-tested against all CRA project shapes (ejected projects, custom webpack configs, unusual CSS tooling). The fallback path (manual step-by-step) needs to be detailed enough for the agent to follow autonomously. Address during Phase 3 template design.
- **React Native Upgrade Helper programmatic access:** The Upgrade Helper is a web UI backed by `rn-diff-purge` data. The agent needs to apply these diffs programmatically. Fetching the diff from the raw rn-diff-purge GitHub data vs fetching it from the Upgrade Helper API vs embedding a known diff is unresolved. Address during Phase 6 planning.
- **Next.js middleware verification without integration tests:** Middleware runs at Edge runtime and is not testable with Jest/Vitest. The recommended approach (next build check + next start manual test) is sound but incomplete for autonomous agents. Whether the agent can reliably run a `next start` + curl check for middleware routes in the Docker container needs validation. Address during Phase 2 template design.
- **CRA proxy fallback path completeness:** The `setupProxy.js` → `vite.config.ts server.proxy` translation involves pattern matching on http-proxy-middleware config formats. The range of valid setupProxy.js patterns in real CRA projects is wide. Address during Phase 3 template design by testing against 3+ real CRA repos.

## Sources

### Primary (HIGH confidence)
- [Next.js Codemods docs](https://nextjs.org/docs/app/guides/upgrading/codemods) — codemod tooling, updated 2026-02-27
- [Next.js 16.1 release blog](https://nextjs.org/blog/next-16-1) — current stable version, feature set
- [Next.js Version 15 + 16 Upgrade Guides](https://nextjs.org/docs/app/guides/upgrading/) — breaking changes, async dynamic APIs, caching semantics, middleware changes
- [React v19 release post](https://react.dev/blog/2024/12/05/react-19) — React 19 breaking changes, useRef, JSX namespace
- [react-codemod GitHub](https://github.com/reactjs/react-codemod) — React 18→19 codemods
- [React.dev: Sunsetting Create React App](https://react.dev/blog/2025/02/14/sunsetting-create-react-app) — CRA end-of-life confirmation
- [Vite 7.0 + migration guides](https://vite.dev/blog/announcing-vite7) — current version, Node version requirements, plugin API changes
- [React Native upgrading docs](https://reactnative.dev/docs/upgrading) — official RN upgrade process
- [React Native 0.82 release](https://reactnative.dev/blog/2025/10/08/react-native-0.82) — New Architecture permanently enabled
- [react-native-community/docker-android Dockerfile](https://github.com/react-native-community/docker-android/blob/main/Dockerfile) — reference image: Ubuntu 22.04, JDK 17, Node 22, SDK 36, NDK 27
- [rnx-kit/align-deps docs](https://microsoft.github.io/rnx-kit/docs/tools/align-deps) — RN ecosystem dependency alignment
- [react-native-community/upgrade-helper](https://github.com/react-native-community/upgrade-helper) — authoritative native file diffs per version pair
- [Vitest migration guide](https://vitest.dev/guide/migration.html) — Jest→Vitest differences
- [React Native Gradle Plugin docs](https://reactnative.dev/docs/react-native-gradle-plugin) — settings.gradle autolinking migration
- Direct analysis of `stacks/laravel/` existing implementation — proven playbook pattern

### Secondary (MEDIUM confidence)
- [Shopify: Migrating to React Native's New Architecture](https://shopify.engineering/react-native-new-architecture) — production New Arch case study
- [Callstack: How to Upgrade React Native in a Brownfield App](https://www.callstack.com/blog/how-to-upgrade-react-native-in-a-brownfield-application) — RN upgrade pitfalls
- [Vercel: Common mistakes with Next.js App Router](https://vercel.com/blog/common-mistakes-with-the-next-js-app-router-and-how-to-fix-them) — RSC boundary pitfalls
- [Robin Wieruch: CRA to Vite migration](https://www.robinwieruch.de/vite-create-react-app/) — CRA→Vite step-by-step reference
- [DEV Community: CRA + Jest to Vite + Vitest lessons learned](https://dev.to/dsychin/lessons-learned-migrating-from-cra-jest-to-vite-vitest-4ahe) — Jest→Vitest migration complexity post-mortem
- [Snyk: Node Docker image analysis](https://snyk.io/blog/choosing-the-best-node-js-docker-image/) — slim vs full vs alpine comparison
- [viject npm](https://www.npmjs.com/package/viject) — v1.3.1, CRA→Vite automated migration tool

### Tertiary (LOW confidence)
- [react-native-upgrader-mcp](https://github.com/patrickkabwe/react-native-upgrader-mcp) — MCP server for RN upgrades; small community, unverified reliability; not recommended for v1
- [App Router Pitfalls — imidef.com](https://imidef.com/en/2026-02-11-app-router-pitfalls) — single source, RSC boundary propagation pattern; needs validation

---
*Research completed: 2026-03-01*
*Ready for roadmap: yes*
