# Requirements: JS Stack Upgrade Agents

**Defined:** 2026-03-01
**Core Value:** Each JS stack agent can autonomously clone a repo, perform the correct upgrade/migration, verify the result, and push a branch with PR.

## v1 Requirements

### Infrastructure

- [x] **INFRA-01**: Shared Node Dockerfile based on node:22-bookworm-slim with Claude CLI, gh CLI, git, jq, envsubst
- [x] **INFRA-02**: Entrypoint auto-detects stack type from package.json after clone (STACK_TYPE env var as optional override)
- [x] **INFRA-03**: JS-specific recon script analyzes package.json deps, framework, test runner, build tool, lockfile type
- [x] **INFRA-04**: verify-fast.sh runs lint + test suite (detects npm test / vitest / jest)
- [x] **INFRA-05**: verify-full.sh runs build + test + lint + npm audit
- [x] **INFRA-06**: Ralph loop works for all JS stacks (restart Claude Code on exit if checklist incomplete)
- [x] **INFRA-07**: Template selection at launch copies from templates/{stack_type}/ into .upgrade/
- [x] **INFRA-08**: Post-build grep checks for known silent-failure markers per stack
- [x] **INFRA-09**: Dependency snapshot diffs (before/after package.json + lockfile) saved to /output/

### Next.js

- [x] **NEXT-01**: Run @next/codemod upgrade for automated transforms
- [x] **NEXT-02**: Handle async request API migration (params, searchParams, cookies, headers)
- [x] **NEXT-03**: Migrate middleware to v2 compatibility
- [x] **NEXT-04**: Migrate to Turbopack config (webpack → turbopack where applicable)
- [x] **NEXT-05**: Verify build succeeds (next build)
- [x] **NEXT-06**: Audit cache semantics for v15+ no-store default change
- [x] **NEXT-07**: Grep for codemod markers (UnsafeUnwrapped, @next/codemod) and resolve or document

### CRA Migration

- [x] **CRA-01**: Run viject for automated CRA→Vite migration (or manual fallback if viject fails)
- [x] **CRA-02**: Rewrite env var prefixes from REACT_APP_ to VITE_ across all source files
- [x] **CRA-03**: Relocate index.html from public/ to project root with script tag injection
- [x] **CRA-04**: Detect and configure SVG imports via vite-plugin-svgr
- [x] **CRA-05**: Translate proxy config (setupProxy.js → vite server.proxy)
- [x] **CRA-06**: Verify build succeeds (vite build)
- [x] **CRA-07**: Detect CI/CD workflow files and flag env vars that need VITE_ prefix
- [x] **CRA-08**: Migrate Jest test suite to Vitest (separate phase from build migration)

### Vite + React

- [x] **VITE-01**: Bump React to target major version and run react-codemod transforms
- [x] **VITE-02**: Bump Vite to target major version and update @vitejs/plugin-react
- [x] **VITE-03**: Handle vite.config format changes between major versions
- [x] **VITE-04**: Verify build succeeds (vite build)
- [x] **VITE-05**: Run types-react-codemod for TypeScript projects

### React Native

- [ ] **RN-01**: Pre-upgrade audit of native module New Architecture compatibility (TurboModules/Fabric)
- [ ] **RN-02**: Run react-native upgrade for version bump
- [ ] **RN-03**: Apply Upgrade Helper diff for config file changes
- [ ] **RN-04**: Update Gradle and settings.gradle configuration
- [ ] **RN-05**: Update Podfile and document pod install requirement (cannot run in Linux Docker)
- [ ] **RN-06**: Verify Android build succeeds (./gradlew assembleDebug)
- [ ] **RN-07**: Run @rnx-kit/align-deps for ecosystem dependency alignment
- [ ] **RN-08**: Separate React Native Dockerfile with JDK 17 + Android SDK 36

### CLI

- [ ] **CLI-01**: Add nextjs stack entry to cli/src/stacks.js with package.json detection
- [ ] **CLI-02**: Add cra stack entry to cli/src/stacks.js with react-scripts detection
- [ ] **CLI-03**: Add vite-react stack entry to cli/src/stacks.js with vite + @vitejs/plugin-react detection
- [ ] **CLI-04**: Add react-native stack entry to cli/src/stacks.js with react-native detection (no expo)
- [ ] **CLI-05**: Detection priority: next > react-scripts > vite+plugin-react > react-native

### CI/CD

- [ ] **CI-01**: Add node stack to release.yml matrix (builds ghcr.io/reyemtech/node-upgrade-agent)
- [ ] **CI-02**: Add react-native stack to release.yml matrix (builds ghcr.io/reyemtech/react-native-upgrade-agent)

## v2 Requirements

### Next.js

- **NEXT-V2-01**: Pages Router → App Router migration mode (separate plan.md)
- **NEXT-V2-02**: Custom webpack → Turbopack automated translation

### React Native

- **RN-V2-01**: Expo upgrade support (separate stack or sub-mode)
- **RN-V2-02**: iOS verification via macOS Kubernetes runner
- **RN-V2-03**: Multi-version skip support (e.g. 0.71→0.84)

### Platform

- **PLAT-V2-01**: Monorepo (Turborepo/Nx) workspace detection and per-package upgrades

## Out of Scope

| Feature | Reason |
|---------|--------|
| Pages Router → App Router conversion | Too complex for autonomous agent v1 — requires understanding data-fetching intent and RSC boundaries |
| iOS build verification in Docker | Impossible — macOS required for Xcode/simulator |
| Expo upgrades | Different upgrade path (expo upgrade CLI), defer to separate stack |
| Angular/Vue/Svelte | Different ecosystems entirely |
| Multi-version RN skips | Each major version has unique breaking changes; sequential upgrades safer |
| Monorepo support | Complex workspace detection, defer |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 1 | Complete |
| INFRA-02 | Phase 1 | Complete |
| INFRA-03 | Phase 1 | Complete |
| INFRA-04 | Phase 1 | Complete |
| INFRA-05 | Phase 1 | Complete |
| INFRA-06 | Phase 1 | Complete |
| INFRA-07 | Phase 1 | Complete |
| INFRA-08 | Phase 1 | Complete |
| INFRA-09 | Phase 1 | Complete |
| NEXT-01 | Phase 2 | Complete |
| NEXT-02 | Phase 2 | Complete |
| NEXT-03 | Phase 2 | Complete |
| NEXT-04 | Phase 2 | Complete |
| NEXT-05 | Phase 2 | Complete |
| NEXT-06 | Phase 2 | Complete |
| NEXT-07 | Phase 2 | Complete |
| CRA-01 | Phase 2 | Complete |
| CRA-02 | Phase 2 | Complete |
| CRA-03 | Phase 2 | Complete |
| CRA-04 | Phase 2 | Complete |
| CRA-05 | Phase 2 | Complete |
| CRA-06 | Phase 2 | Complete |
| CRA-07 | Phase 2 | Complete |
| CRA-08 | Phase 2 | Complete |
| VITE-01 | Phase 2 | Complete |
| VITE-02 | Phase 2 | Complete |
| VITE-03 | Phase 2 | Complete |
| VITE-04 | Phase 2 | Complete |
| VITE-05 | Phase 2 | Complete |
| RN-01 | Phase 3 | Pending |
| RN-02 | Phase 3 | Pending |
| RN-03 | Phase 3 | Pending |
| RN-04 | Phase 3 | Pending |
| RN-05 | Phase 3 | Pending |
| RN-06 | Phase 3 | Pending |
| RN-07 | Phase 3 | Pending |
| RN-08 | Phase 3 | Pending |
| CLI-01 | Phase 4 | Pending |
| CLI-02 | Phase 4 | Pending |
| CLI-03 | Phase 4 | Pending |
| CLI-04 | Phase 4 | Pending |
| CLI-05 | Phase 4 | Pending |
| CI-01 | Phase 4 | Pending |
| CI-02 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 43 total
- Mapped to phases: 43
- Unmapped: 0

---
*Requirements defined: 2026-03-01*
*Last updated: 2026-03-01 — traceability filled after roadmap creation*
