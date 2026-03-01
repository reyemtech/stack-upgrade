# JS Stack Upgrade Agents

## What This Is

Four new upgrade agent stacks for the stack-upgrade monorepo, covering the JavaScript/React ecosystem. A shared Node-based Docker image handles Next.js upgrades, CRA-to-Vite migrations, and Vite+React upgrades. A separate image handles React Native upgrades (due to Android SDK requirements). The CLI auto-detects stack type from package.json and queues upgrades alongside existing Laravel support.

## Core Value

Each JS stack agent can autonomously clone a repo, perform the correct upgrade/migration, verify the result, and push a branch with PR — same quality bar as the existing Laravel agent.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Next.js major version upgrade agent (e.g. 13→14→15)
- [ ] CRA-to-Vite migration agent (react-scripts → Vite)
- [ ] Vite+React major version upgrade agent (React + Vite version bumps)
- [ ] React Native major version upgrade agent (bare RN, no Expo)
- [ ] Shared Node Docker image for web JS stacks (Next.js, CRA, Vite-React)
- [ ] Separate React Native Docker image (Android SDK + JDK)
- [ ] Auto-detection of JS stack type from package.json in entrypoint
- [ ] CLI stack registry entries for all 4 new stacks
- [ ] CLI auto-detects JS stacks during repo discovery (package.json-based)
- [ ] Stack-specific templates (CLAUDE.md, plan.md, checklist.yaml) for each stack
- [ ] Stack-specific recon script for JS projects
- [ ] Stack-specific verify scripts (fast + full) for JS projects
- [ ] Ralph loop works for all JS stacks
- [ ] CI matrix builds node + react-native images
- [ ] All stacks work via both CLI and raw `docker run`

### Out of Scope

- Expo upgrades — Expo has `expo upgrade` CLI, different enough to defer
- Remix upgrades — smaller market, add later if demand exists
- Angular/Vue/Svelte — different ecosystems entirely, future stacks
- Monorepo (Turborepo/Nx) support — complex workspace detection, defer
- Auto-detecting between Expo and bare React Native — v1 assumes bare RN

## Context

This project extends the existing stack-upgrade monorepo which already has a working Laravel upgrade agent. The architecture supports multiple stacks via `cli/src/stacks.js` registry and a CI matrix that builds per-stack Docker images.

Key architectural decision: web JS stacks (Next.js, CRA, Vite-React) share a single Docker image (`ghcr.io/reyemtech/node-upgrade-agent`) with stack-specific templates selected at launch. React Native gets a separate image due to Android SDK/JDK requirements (~1GB+ of tooling).

The entrypoint auto-detects stack type from package.json after cloning, so `STACK_TYPE` env var is optional (override only). This keeps `docker run` ergonomics clean.

Following the Nayeem Zen Playbook v8 pattern: templates baked into image, three-file memory system (plan.md, checklist.yaml, run-log.md), ralph loop for restart resilience, recon before action.

## Constraints

- **Monorepo structure**: Must follow existing `stacks/{name}/` convention
- **CLI compatibility**: New stacks must integrate with existing CLI flow (discovery, multi-select, Docker/K8s launch)
- **Playbook compliance**: Three-file memory, ralph loop, recon-before-action, one-commit-per-phase
- **Image size**: Node image should stay lean (~500MB). RN image will be large (~2GB) due to Android SDK — acceptable.
- **Detection priority**: When package.json has both `next` and `vite`, Next.js takes priority (it's the framework)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Shared Node image for web JS stacks | CRA, Next.js, Vite-React all need Node + same tooling. Avoids 3 near-identical Dockerfiles. | — Pending |
| Separate React Native image | Android SDK + JDK too large/different to share with web stacks | — Pending |
| CRA agent is a migration (not upgrade) | CRA is dead/unmaintained. Only useful action is migrating to Vite. | — Pending |
| Auto-detect stack from package.json | Keeps `docker run` ergonomic without requiring STACK_TYPE env var | — Pending |
| Templates baked in image, selected at launch | Playbook compliance — survives context compaction. No volume mounts needed. | — Pending |
| Separate stacks per framework (not one "React" stack) | Each framework has fundamentally different upgrade paths, breaking changes, and tooling | — Pending |

---
*Last updated: 2026-03-01 after initialization*
