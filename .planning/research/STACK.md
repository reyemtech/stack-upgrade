# Stack Research

**Domain:** Autonomous JS upgrade/migration agents inside Docker containers
**Researched:** 2026-03-01
**Confidence:** MEDIUM-HIGH (versions verified via web search against official sources)

---

## Context

This research covers the standard 2025/2026 stack for building autonomous upgrade agents for four JS targets:

1. **Next.js** — major version upgrade (e.g. 14→15→16)
2. **CRA→Vite** — migration away from dead react-scripts to Vite
3. **Vite+React** — version bump (Vite 5→6→7, React 18→19)
4. **React Native** — bare workflow major version upgrade (e.g. 0.72→0.84)

The agent runs inside Docker, clones a target repo, runs codemods + package upgrades autonomously, verifies the result, and pushes a branch with a PR. This mirrors the existing Laravel stack pattern.

---

## Current Version Landscape (March 2026)

| Framework | Current Stable | Notes |
|-----------|---------------|-------|
| Next.js | 16.1 | Released Dec 2025. Turbopack stable and default. |
| React | 19.0 | Released Dec 2024. Stable. |
| Vite | 7.x | Advanced beyond v6. Node 20.19+ or 22.12+ required. |
| Vite plugin-react | latest | Tracks Vite major. |
| React Native | 0.84 | Released ~Feb 2026. React 19 support from 0.78+. |
| Node.js (LTS) | 22 (Active LTS) | Debian Bookworm packages available. |

**Sources:** [Next.js 16.1 blog](https://nextjs.org/blog/next-16-1), [React v19](https://react.dev/blog/2024/12/05/react-19), [Vite releases](https://vite.dev/releases), [RN releases](https://github.com/facebook/react-native/releases)

---

## Recommended Stack

### Docker Base Images

| Image | Stack(s) | Why |
|-------|---------|-----|
| `node:22-bookworm-slim` | Next.js, CRA→Vite, Vite+React (shared) | Active LTS, slim variant cuts attack surface and image size vs full, Bookworm supported until ~2028. Consistent with the existing Laravel stack's Debian Bookworm base. |
| Custom from `ubuntu:22.04` or `node:22-bookworm-slim` + Android SDK | React Native | RN needs JDK 17 + Android SDK 36 + NDK. The community-maintained `react-native-community/docker-android` image uses Ubuntu 22.04 + OpenJDK 17 as a reference. |

**Why NOT `node:22` (full):** Adds ~1GB and ~900 extra vulnerabilities vs slim for zero benefit in a non-GUI CI agent. [Snyk analysis](https://snyk.io/blog/choosing-the-best-node-js-docker-image/).

**Why NOT `node:24` or `node:latest`:** LTS stability matters for build tools. Node 22 is Active LTS through 2027. Node 24 will be LTS in October 2026 — adopt then.

### System Dependencies (Web Node image)

| Dependency | Version | Why |
|------------|---------|-----|
| `git` | OS default | Clone, branch, commit |
| `gh` CLI | latest | Auto PR creation (same pattern as Laravel stack) |
| `gettext-base` | OS default | `envsubst` for template variable substitution |
| `jq` | OS default | JSON parsing in shell scripts |
| `curl` | OS default | Fetching upgrade guides (same as Laravel) |
| `ssh-client` | OS default | SSH clone support |
| `@anthropic-ai/claude-code` | latest | The agent runtime |

### React Native Additional Dependencies

| Dependency | Version | Why |
|------------|---------|-----|
| `openjdk-17-jdk-headless` | 17 | RN 0.84 officially requires JDK 17. JDK 21 causes Gradle/Kotlin incompatibilities. [RN CLI issue #2044](https://github.com/react-native-community/cli/issues/2044) |
| Android SDK Command-line Tools | latest (11076708+) | Required for sdkmanager, avdmanager |
| Android Build-Tools | 36.0.0 | Current SDK 36 (VanillaIceCream API level 35/36) |
| Android NDK | 27.1.12297006 | Current NDK per react-native-community/docker-android |
| CMake | 3.30.5 | Required for native builds |

**Reference:** [react-native-community/docker-android Dockerfile](https://github.com/react-native-community/docker-android/blob/main/Dockerfile) — Ubuntu 22.04, OpenJDK 17, Node 22.14, SDK 36, NDK 27.

---

## Codemod / Upgrade Tooling Per Stack

### Next.js Upgrade Agent

**Primary tool:** `@next/codemod` — the official Vercel-maintained codemod runner. Confidence: HIGH (verified via [official docs](https://nextjs.org/docs/app/guides/upgrading/codemods), docs updated 2026-02-27).

```bash
# One command upgrades packages + runs appropriate codemods:
npx @next/codemod upgrade major     # to latest major
npx @next/codemod upgrade 16        # to specific version

# Individual codemods (run automatically by `upgrade`, but can be run standalone):
npx @next/codemod@latest next-async-request-api .   # 15.0: async cookies/headers/draftMode
npx @next/codemod@latest remove-experimental-ppr .  # 16.0: PPR route segment config
npx @next/codemod@latest remove-unstable-prefix .   # 16.0: stabilized APIs
npx @next/codemod@latest middleware-to-proxy .       # 16.0: middleware→proxy rename
npx @next/codemod@latest next-lint-to-eslint-cli .  # 16.0: next lint → ESLint CLI
```

**React 19 codemods** (needed when Next.js upgrade bumps React):
```bash
# Official react-codemod (maintained with React team + codemod.com):
npx react-codemod@latest
```

Key transforms: `Context.Provider` → `Context`, `forwardRef` removal, `useFormState` → `useActionState`, `useContext` → `use`.

**TypeScript-specific:**
```bash
npx types-react-codemod@latest preset-19 ./src
```

**Upgrade strategy for agent:**
1. Read `package.json` to determine current Next.js major version.
2. Run `npx @next/codemod upgrade [target_version]` — this handles package bumps + codemod selection interactively. In non-interactive mode, pass `--yes` flag if available, or pipe answers.
3. Run `next build` to catch residual issues.
4. Fix any remaining type errors flagged by `UnsafeUnwrapped` comments left by codemod.

**Pages Router vs App Router awareness:** Codemods differ. The agent must detect which router is in use from the directory structure (`app/` vs `pages/` at root level).

### CRA→Vite Migration Agent

CRA (`create-react-app` / `react-scripts`) is **officially sunset as of Feb 2025**. The React team no longer recommends it. This agent's job is a one-way migration to Vite, not an upgrade of CRA itself.

**Primary tool:** `viject` — one-shot CRA→Vite migration. Confidence: MEDIUM (npm package active, 175 downloads/week, last published ~Mar 2026, v1.3.1).

```bash
npx viject
```

What it does: removes `react-scripts`, updates `package.json` scripts, updates `gitignore`, updates `tsconfig.json`, generates `vite.config.ts`, handles environment variable differences (`REACT_APP_*` → `VITE_*`).

**Secondary tool (for projects viject can't fully handle):** Manual step-by-step following [robinwieruch.de/vite-create-react-app](https://www.robinwieruch.de/vite-create-react-app/).

**React 19 codemod** (apply if also upgrading React as part of migration):
Same as above — `npx react-codemod@latest`.

**Critical migration concerns:**
- Environment variables: `process.env.REACT_APP_X` → `import.meta.env.VITE_X`
- `index.html` moves from `/public/index.html` to root `/index.html` with Vite script tag
- `process.env.NODE_ENV` → `import.meta.env.MODE` in some patterns
- Jest → Vitest migration is adjacent but distinct — defer unless test suite is fully broken
- CSS/PostCSS config mostly transfers unchanged

**Verification:** `npm run build` (Vite build). Then fast check that dev server starts.

### Vite+React Upgrade Agent

Target: repos already using Vite (not CRA). Upgrading Vite 4/5 → 7 and React 18 → 19.

**No single official codemod tool** — this is package bumps + React 19 codemods. Confidence: MEDIUM.

```bash
# Step 1: Upgrade Vite and plugin
npm install -D vite@latest @vitejs/plugin-react@latest

# Step 2: Upgrade React
npm install react@19 react-dom@19

# Step 3: React 19 codemods
npx react-codemod@latest
npx types-react-codemod@latest preset-19 ./src   # TypeScript projects

# Step 4: Upgrade Vitest if present (Vitest 3 supports Vite 6/7)
npm install -D vitest@latest
```

**Vite-specific breaking changes to handle:**
- Node 20.19+ or 22.12+ required for Vite 6+ (verify in Dockerfile — Node 22 satisfies this)
- `vite.config.js` API changes between major versions — check [Vite migration guide](https://v4.vite.dev/releases)
- `@vitejs/plugin-react` vs `@vitejs/plugin-react-swc` — agent should detect which is in use and upgrade the correct one

**Verification:** `npm run build`. Type-check with `tsc --noEmit` if TypeScript.

### React Native Upgrade Agent

Bare workflow only (no Expo). Target: upgrading from older RN (e.g. 0.72) to latest stable (0.84 as of Mar 2026).

**Primary tool:** `react-native upgrade` CLI command (via `@react-native-community/cli`). Confidence: HIGH (official docs, uses `rn-diff-purge` internally).

```bash
# Step 1: Bump the package
npm install react-native@0.84

# Step 2: Run the CLI upgrade (applies native file changes)
npx react-native upgrade

# Step 3: Align all RN ecosystem dependencies
npx @rnx-kit/align-deps --requirements react-native@0.84 --write
```

**Reference tool:** [React Native Upgrade Helper](https://react-native-community.github.io/upgrade-helper/) — web tool showing diff of native files between any two versions. The agent should fetch this diff programmatically via the `rn-diff-purge` dataset or the web tool URL, then apply changes.

**`@rnx-kit/align-deps`** (Microsoft-maintained): Resolves all third-party RN ecosystem packages (navigation, gesture handler, etc.) to versions compatible with the target RN version. Essential — without it, dependency hell is near-certain. Confidence: HIGH ([official docs](https://microsoft.github.io/rnx-kit/docs/tools/align-deps)).

```bash
npx @rnx-kit/align-deps --requirements react-native@0.84 --write
```

**React 19 codemods** (RN 0.78+ ships React 19):
```bash
npx react-codemod@latest
```

**iOS native changes:** `npx pod-install` after JS upgrade (requires macOS — the Docker agent cannot build/test iOS. iOS verification is out of scope for the Docker agent; scope to Android + JS layer.)

**Android verification:** `cd android && ./gradlew assembleDebug` — validates the Gradle/Java/NDK stack compiles. This is the key gate for the RN Docker agent.

**MCP tool for RN:** [react-native-upgrader-mcp](https://github.com/patrickkabwe/react-native-upgrader-mcp) — an MCP server that wraps `rn-diff-purge` for upgrade automation. Claude Code supports MCP tools — this is worth evaluating as an alternative to shell-level upgrade commands. Confidence: LOW (small community project, unverified reliability).

---

## Stack Patterns by Agent Variant

**If Next.js (Pages Router detected — `pages/` directory exists, no `app/` directory):**
- Use `@next/codemod upgrade` as primary
- Pages Router codemods apply (13.x `new-link`, `next-image-*`)
- Be aware: 13→14 was low-friction, 14→15 introduced async request APIs (major codemod needed), 15→16 renamed middleware to proxy

**If Next.js (App Router detected — `app/` directory exists):**
- Same tooling but different codemod scope
- `next-async-request-api` codemod is critical for 15.x upgrade
- Check for `"use client"` / `"use server"` directive usage

**If CRA (react-scripts in package.json):**
- Run `viject` first
- If `viject` fails or leaves broken config, fall back to manual steps
- Always check for `REACT_APP_*` env vars — these need renaming to `VITE_*`

**If Vite+React (vite in devDependencies, no react-scripts):**
- Pure package bumps + React 19 codemods
- No structural migration needed — just version alignment

**If React Native (react-native in dependencies, no expo dependency):**
- Confirm bare workflow: look for `android/` and `ios/` directories
- Android-only verification in Docker (iOS skipped — requires macOS)
- JDK 17 required in Docker image

---

## Alternatives Considered

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| `@next/codemod upgrade` | Manual `npm install next@latest` | `@next/codemod` handles codemods + package bump atomically. Manual approach misses the API transform step. |
| `viject` for CRA→Vite | `@next/codemod cra-to-next` | cra-to-next migrates to Next.js, not Vite. Wrong target for this agent. |
| `@rnx-kit/align-deps` | Manual `npm install` each RN dep | align-deps has a curated compatibility matrix; manual approach misses transitive peer dep conflicts. |
| `react-native upgrade` CLI | Manually applying Upgrade Helper diffs | CLI is one command vs reading and applying a web-based diff. Better for autonomous agents. |
| `node:22-bookworm-slim` base | `node:22-alpine` | Alpine uses musl libc which causes issues with native npm packages (bcrypt, canvas, etc.) common in React/Next.js apps. Bookworm is safer for unknown target repos. |
| OpenJDK 17 for RN | JDK 21 | RN 0.84 officially supports JDK 17. JDK 21+ causes Gradle/Kotlin incompatibilities as of Mar 2026. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `react-scripts` (CRA) | Officially sunset Feb 2025. No security fixes. Dead. | Vite |
| `@next/codemod cra-to-next` for this project | Migrates to Next.js, not Vite — wrong output for CRA→Vite agent | `viject` |
| `node:22-alpine` as base | musl libc breaks many native deps silently | `node:22-bookworm-slim` |
| JDK 21+ in RN Docker image | Gradle/Kotlin incompatibility with RN 0.84 | JDK 17 (`openjdk-17-jdk-headless`) |
| Expo `expo upgrade` CLI | Out of scope per PROJECT.md. Different enough to warrant its own stack. | Defer to future stack |
| `npm install --legacy-peer-deps` as default | Masks real peer dep conflicts that will surface at runtime | Fix deps properly; only use as last resort with explicit logging |
| Running iOS build in Docker | macOS-only Xcode toolchain cannot run in Linux Docker | Scope RN verification to Android (`./gradlew assembleDebug`) |

---

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| `vite@7.x` | `node@22+` (requires 20.19+ or 22.12+) | Node 22 satisfies this. Do NOT use Node 18. |
| `@vitejs/plugin-react@latest` | `vite@6.x`, `vite@7.x` | Tracks Vite major. |
| `react-native@0.84` | `node@22`, `JDK 17`, `Android SDK 36` | JDK 21 causes Gradle failures. |
| `@rnx-kit/align-deps` | `react-native@0.66+` | Works with any modern RN version. |
| `@next/codemod upgrade` | `next@13+` | Can upgrade across multiple major versions. |
| `react@19` | `next@15+`, `vite-plugin-react@latest`, `react-native@0.78+` | React 19 requires framework support. Next.js 14 is on React 18. |

---

## Node Image Size Targets

Per PROJECT.md constraints:

- Web Node image (Next.js, CRA, Vite-React): target ~500MB
- React Native image: ~2GB acceptable (Android SDK is ~1.5GB)

`node:22-bookworm-slim` base is ~200MB, leaving headroom for gh CLI, git, jq, curl, and claude-code global npm install.

---

## Sources

- [Next.js Codemods docs](https://nextjs.org/docs/app/guides/upgrading/codemods) — HIGH confidence, updated 2026-02-27
- [Next.js 16.1 release blog](https://nextjs.org/blog/next-16-1) — HIGH confidence (official)
- [React v19 release post](https://react.dev/blog/2024/12/05/react-19) — HIGH confidence (official)
- [react-codemod GitHub](https://github.com/reactjs/react-codemod) — HIGH confidence (official)
- [Codemod.com React 18→19 guide](https://docs.codemod.com/guides/migrations/react-18-19) — MEDIUM confidence (official codemod.com)
- [Vite releases](https://vite.dev/releases) — HIGH confidence (official)
- [React Native upgrading docs](https://reactnative.dev/docs/upgrading) — HIGH confidence (official)
- [react-native-community/upgrade-helper](https://github.com/react-native-community/upgrade-helper) — HIGH confidence (official community)
- [react-native-community/docker-android Dockerfile](https://github.com/react-native-community/docker-android/blob/main/Dockerfile) — HIGH confidence (reference image: Ubuntu 22.04, JDK 17, Node 22, SDK 36, NDK 27)
- [rnx-kit/align-deps docs](https://microsoft.github.io/rnx-kit/docs/tools/align-deps) — HIGH confidence (Microsoft official)
- [viject npm](https://www.npmjs.com/package/viject) — MEDIUM confidence (v1.3.1, active but small community)
- [Docker node:22-bookworm-slim](https://hub.docker.com/layers/library/node/22-bookworm-slim/) — HIGH confidence (official Docker Hub)
- [Snyk Node Docker image analysis](https://snyk.io/blog/choosing-the-best-node-js-docker-image/) — MEDIUM confidence (third-party but thorough)
- [react-native-upgrader-mcp](https://github.com/patrickkabwe/react-native-upgrader-mcp) — LOW confidence (small community project)

---

*Stack research for: JS upgrade/migration agents (Next.js, CRA→Vite, Vite+React, React Native)*
*Researched: 2026-03-01*
