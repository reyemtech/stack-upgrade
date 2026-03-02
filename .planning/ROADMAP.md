# Roadmap: JS Stack Upgrade Agents

## Overview

Four upgrade agent stacks (Next.js, CRA→Vite, Vite+React, React Native) are added to the existing stack-upgrade monorepo in four phases: shared Node infrastructure first, then web JS templates for all three web stacks together, then the heavy React Native image and templates, then CLI registry and CI matrix wiring. Each phase delivers a complete, runnable capability before the next phase depends on it.

## Phases

- [x] **Phase 1: Shared Node Image Foundation** - Dockerfile, entrypoint with auto-detection, and shared scripts for all web JS stacks (completed 2026-03-01)
- [ ] **Phase 2: Web JS Agent Templates** - Next.js, CRA, and Vite+React template sets (CLAUDE.md, plan.md, checklist.yaml per stack)
- [ ] **Phase 3: React Native Image and Templates** - Separate heavy image with Android SDK and RN-specific scripts and templates
- [ ] **Phase 4: CLI Registry and CI Matrix** - Wire all four stacks into CLI detection and CI multi-arch builds

## Phase Details

### Phase 1: Shared Node Image Foundation
**Goal**: A runnable `stacks/node/` Docker image exists that can clone a JS repo, detect its stack type from package.json, run recon, execute verify scripts, and restart via the ralph loop
**Depends on**: Nothing (first phase)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-04, INFRA-05, INFRA-06, INFRA-07, INFRA-08, INFRA-09
**Success Criteria** (what must be TRUE):
  1. `docker build stacks/node/` completes without error and produces an image under 600MB
  2. Running the image against a Next.js repo with `STACK_TYPE` unset detects `nextjs` from package.json and selects the correct template directory
  3. `verify-fast.sh` exits 0 on a project with passing lint and tests; exits non-zero when lint or tests fail
  4. Ralph loop restarts Claude Code on exit and writes updated `status.json` after each restart
  5. Before/after dependency snapshots appear in `/output/` after a completed run
**Plans**: 3 plans

Plans:
- [ ] 01-01-PLAN.md — Dockerfile, detect-stack.sh, entrypoint.sh, placeholder templates
- [ ] 01-02-PLAN.md — verify-fast.sh, verify-full.sh, recon.sh
- [ ] 01-03-PLAN.md — ralph-loop.sh, stream-pretty.sh, kickoff-prompt.txt

### Phase 2: Web JS Agent Templates
**Goal**: All three web JS upgrade/migration workflows (Next.js major upgrade, CRA→Vite migration, Vite+React version bump) have complete agent template sets that guide Claude Code through the correct phase sequence for each stack
**Depends on**: Phase 1
**Requirements**: NEXT-01, NEXT-02, NEXT-03, NEXT-04, NEXT-05, NEXT-06, NEXT-07, CRA-01, CRA-02, CRA-03, CRA-04, CRA-05, CRA-06, CRA-07, CRA-08, VITE-01, VITE-02, VITE-03, VITE-04, VITE-05
**Success Criteria** (what must be TRUE):
  1. Running the node image against a Next.js 14 repo with `TARGET_NEXTJS=15` produces a branch where `@next/codemod upgrade` has run, no `UnsafeUnwrapped` markers remain in source, and `next build` exits 0
  2. Running the node image against a CRA repo produces a branch where `react-scripts` is removed, `vite.config.ts` exists, `REACT_APP_*` references are rewritten to `VITE_*`, and `vite build` exits 0
  3. Running the node image against a Vite+React repo produces a branch where React and Vite are bumped to target major versions and `vite build` exits 0
  4. Post-build grep checks (`verify-fast.sh`) catch known silent-failure markers (codemod markers, leftover `process.env.REACT_APP_` in `dist/`) and exit non-zero when found
**Plans**: 3 plans

Plans:
- [ ] 02-01-PLAN.md — Next.js templates (CLAUDE.md, plan.md, checklist.yaml) + entrypoint.sh URL fix
- [ ] 02-02-PLAN.md — CRA templates (CLAUDE.md, plan.md, checklist.yaml)
- [ ] 02-03-PLAN.md — Vite+React templates (CLAUDE.md, plan.md, checklist.yaml)

### Phase 3: React Native Image and Templates
**Goal**: A runnable `stacks/react-native/` Docker image exists with JDK 17 and Android SDK that can perform a bare React Native major version upgrade, audit New Architecture library compatibility before any version bump, and verify the Android build succeeds
**Depends on**: Phase 1
**Requirements**: RN-01, RN-02, RN-03, RN-04, RN-05, RN-06, RN-07, RN-08
**Success Criteria** (what must be TRUE):
  1. `docker build stacks/react-native/` completes and the image includes JDK 17, Android SDK 36, and NDK 27
  2. Running the image against a bare RN repo produces a pre-upgrade audit report of native modules against New Architecture compatibility before any package version is changed
  3. Running the image against a bare RN repo with `TARGET_RN=0.77` produces a branch where `react-native upgrade` has run, Gradle and AGP versions match the target release, and `./gradlew assembleDebug` exits 0 (when `ANDROID_BUILD=true`)
  4. `verify-fast.sh` for RN includes a `./gradlew --version` check that catches Gradle/AGP version mismatch
**Plans**: 3 plans

Plans:
- [ ] 03-01-PLAN.md — Dockerfile (Ubuntu 22.04 + JDK 17 + Android SDK 36) + entrypoint.sh + kickoff-prompt.txt + shared templates
- [ ] 03-02-PLAN.md — Scripts: verify-fast.sh (Gradle/AGP check + iOS), verify-full.sh (assembleDebug), recon.sh, ralph-loop.sh, stream-pretty.sh
- [ ] 03-03-PLAN.md — Templates: CLAUDE.md (agent instructions), plan.md (6-phase upgrade plan), checklist.yaml

### Phase 4: CLI Registry and CI Matrix
**Goal**: All four new stacks are discoverable and launchable via the `stack-upgrade` CLI, and the CI pipeline builds and publishes both new Docker images on every release
**Depends on**: Phase 2, Phase 3
**Requirements**: CLI-01, CLI-02, CLI-03, CLI-04, CLI-05, CI-01, CI-02
**Success Criteria** (what must be TRUE):
  1. Running `stack-upgrade` on a machine with a Next.js repo in scope shows `nextjs` as a detected stack option and launches `ghcr.io/reyemtech/node-upgrade-agent`
  2. Stack detection priority (next > react-scripts > vite+react > react-native) is enforced — a repo with both `next` and `vite` in package.json is detected as `nextjs`, not `vite-react`
  3. Merging to main triggers CI builds for both `node-upgrade-agent` and `react-native-upgrade-agent` in the matrix, producing amd64 and arm64 images published to ghcr.io
**Plans**: TBD

## Progress

**Execution Order:** 1 → 2 → 3 (parallel with 2) → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Shared Node Image Foundation | 3/3 | Complete    | 2026-03-01 |
| 2. Web JS Agent Templates | 0/3 | Not started | - |
| 3. React Native Image and Templates | 0/3 | Not started | - |
| 4. CLI Registry and CI Matrix | 0/TBD | Not started | - |
