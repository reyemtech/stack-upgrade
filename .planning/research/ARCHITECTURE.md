# Architecture Research

**Domain:** Autonomous JS upgrade agents (multi-stack monorepo)
**Researched:** 2026-03-01
**Confidence:** HIGH (based on direct analysis of existing Laravel implementation + confirmed design decisions in PROJECT.md)

---

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CLI Layer                                    │
│   cli/src/stacks.js (registry)  ←  cli/src/index.js (orchestrator) │
│   detect from package.json          docker.js / kubectl.js           │
└────────────────────────┬────────────────────────────────────────────┘
                         │  docker run / kubectl apply
          ┌──────────────┴──────────────────────────────────┐
          │                                                  │
┌─────────▼───────────────────────┐    ┌────────────────────▼──────────┐
│     stacks/node/                │    │   stacks/react-native/         │
│  (shared Node Docker image)     │    │   (separate RN Docker image)   │
│                                 │    │                                 │
│  Dockerfile                     │    │  Dockerfile                     │
│   - Node 22 LTS                 │    │   - Node 22 LTS                 │
│   - npm / npx                   │    │   - JDK 17                      │
│   - gh CLI                      │    │   - Android SDK                 │
│   - Claude Code                 │    │   - gh CLI                      │
│   - gettext-base (envsubst)     │    │   - Claude Code                 │
│   - jq, git, ssh-client         │    │   - jq, git, ssh-client         │
│                                 │    │                                 │
│  entrypoint.sh                  │    │  entrypoint.sh                  │
│   - validate env                │    │   - validate env                │
│   - clone repo                  │    │   - clone repo                  │
│   - AUTO-DETECT stack type      │    │   - install npm deps            │
│   - select templates            │    │   - drop RN templates           │
│   - install npm deps            │    │   - recon (RN-specific)         │
│   - drop stack templates        │    │   - ralph-loop.sh               │
│   - recon.sh                    │    │                                 │
│   - ralph-loop.sh               │    │  templates/                     │
│                                 │    │   react-native/                 │
│  templates/                     │    │     CLAUDE.md                   │
│   nextjs/                       │    │     plan.md                     │
│     CLAUDE.md                   │    │     checklist.yaml              │
│     plan.md                     │    │     run-log.md                  │
│     checklist.yaml              │    │     changelog.md                │
│     run-log.md                  │    │                                 │
│     changelog.md                │    │  scripts/                       │
│   cra/                          │    │   recon.sh                      │
│     CLAUDE.md                   │    │   verify-fast.sh                │
│     plan.md                     │    │   verify-full.sh                │
│     checklist.yaml              │    │   ralph-loop.sh                 │
│     run-log.md                  │    │   stream-pretty.sh              │
│     changelog.md                │    │                                 │
│   vite-react/                   │    └─────────────────────────────────┘
│     CLAUDE.md                   │
│     plan.md                     │
│     checklist.yaml              │
│     run-log.md                  │
│     changelog.md                │
│                                 │
│  scripts/                       │
│   recon.sh                      │
│   verify-fast.sh                │
│   verify-full.sh                │
│   ralph-loop.sh                 │
│   stream-pretty.sh              │
│                                 │
└─────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| `cli/src/stacks.js` | Stack registry: detection logic, image name, env key, branch prefix | CLI orchestrator, Docker/K8s launchers |
| `cli/src/index.js` | Multi-upgrade loop: discover repos, prompt user, queue runs | stacks.js, docker.js, kubectl.js |
| `stacks/node/Dockerfile` | Lean Node image (~500MB): Node 22, gh CLI, Claude Code, envsubst | Built by CI matrix |
| `stacks/node/entrypoint.sh` | Clone → detect stack → drop templates → recon → ralph | ralph-loop.sh, recon.sh, /skill/templates/{stack}/ |
| `stacks/node/templates/{stack}/` | Agent instructions baked into image; selected at launch by entrypoint | envsubst substitution at launch time |
| `stacks/node/scripts/recon.sh` | Pre-run analysis of JS project: package.json, test runner, build tool | Writes .upgrade/recon-report.md |
| `stacks/node/scripts/verify-fast.sh` | Quick validation: lint, type-check, unit tests | Called by Claude Code agent after each change |
| `stacks/node/scripts/verify-full.sh` | Full validation: build, integration tests, audit | Called before marking any phase complete |
| `stacks/node/scripts/ralph-loop.sh` | Restart harness: relaunch Claude Code if checklist incomplete | Writes /output/status.json, result.json |
| `stacks/react-native/Dockerfile` | Heavy RN image (~2GB): Node + JDK 17 + Android SDK | Built separately in CI matrix |
| `stacks/react-native/entrypoint.sh` | Same flow as node entrypoint but no detection needed (single stack) | ralph-loop.sh, RN-specific scripts |

---

## Recommended Project Structure

```
stacks/
├── laravel/                        # Existing (unchanged)
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── kickoff-prompt.txt
│   ├── scripts/
│   └── templates/
│
├── node/                           # NEW: shared web JS image
│   ├── Dockerfile                  # Node 22, gh CLI, Claude Code (~500MB)
│   ├── entrypoint.sh               # clone → detect → select templates → recon → ralph
│   ├── kickoff-prompt.txt          # Generic JS kickoff; references .upgrade/CLAUDE.md
│   ├── scripts/
│   │   ├── recon.sh                # JS-specific: package.json analysis, test runner detection
│   │   ├── verify-fast.sh          # npm run lint + tsc --noEmit + unit tests
│   │   ├── verify-full.sh          # above + npm run build + npm audit
│   │   ├── ralph-loop.sh           # Same pattern as Laravel ralph-loop.sh
│   │   └── stream-pretty.sh        # Same as Laravel (copy or symlink)
│   └── templates/
│       ├── nextjs/                 # Selected when STACK_TYPE=nextjs
│       │   ├── CLAUDE.md           # Next.js-specific upgrade instructions
│       │   ├── plan.md             # 6-phase Next.js upgrade plan
│       │   ├── checklist.yaml      # Next.js phase tracking
│       │   ├── run-log.md          # Empty log template
│       │   └── changelog.md        # Empty changelog template
│       ├── cra/                    # Selected when STACK_TYPE=cra
│       │   ├── CLAUDE.md           # CRA→Vite migration instructions
│       │   ├── plan.md             # Migration plan (not upgrade)
│       │   ├── checklist.yaml
│       │   ├── run-log.md
│       │   └── changelog.md
│       └── vite-react/             # Selected when STACK_TYPE=vite-react
│           ├── CLAUDE.md           # Vite+React upgrade instructions
│           ├── plan.md             # React + Vite version bump plan
│           ├── checklist.yaml
│           ├── run-log.md
│           └── changelog.md
│
└── react-native/                   # NEW: separate RN image
    ├── Dockerfile                  # Node + JDK 17 + Android SDK (~2GB)
    ├── entrypoint.sh               # clone → install → drop templates → recon → ralph
    ├── kickoff-prompt.txt
    ├── scripts/
    │   ├── recon.sh                # RN-specific: Metro config, native modules, Gradle version
    │   ├── verify-fast.sh          # npm run lint + jest --testPathPattern=unit
    │   ├── verify-full.sh          # above + TypeScript check + Android build (if ANDROID_BUILD=true)
    │   ├── ralph-loop.sh           # Same pattern
    │   └── stream-pretty.sh
    └── templates/
        └── react-native/           # Only one stack, no detection needed
            ├── CLAUDE.md
            ├── plan.md
            ├── checklist.yaml
            ├── run-log.md
            └── changelog.md

cli/src/
├── stacks.js                       # Add nextjs, cra, vite-react, react-native entries
├── github.js                       # Add JS detection: reads package.json (not composer.json)
└── ...                             # Unchanged
```

### Structure Rationale

- **`stacks/node/templates/{stack}/`:** All three web JS stack template sets live inside the single node image. The entrypoint selects the correct subdirectory at launch based on detected or provided `STACK_TYPE`. This avoids three near-identical Dockerfiles while maintaining clean template separation per framework.
- **`stacks/react-native/`:** Entirely separate directory and image. The Android SDK and JDK make it impossible to share with the lean web image without inflating it to 2GB. The structural pattern (scripts, templates, entrypoint) is identical — only the Dockerfile base layers and verify scripts differ.
- **`scripts/` at image level:** All scripts are shared across the three web JS stacks within the node image. Verification commands differ per framework but can be made uniform via `npm run build`, `npm test`, `npm run lint` — conventions all three stacks follow.

---

## Architectural Patterns

### Pattern 1: Auto-Detection in Entrypoint (JS-specific, differs from Laravel)

**What:** After cloning, the node entrypoint reads `package.json` to determine which template set to drop into `.upgrade/`. Laravel's entrypoint skips this — `TARGET_LARAVEL` is always required. The node entrypoint makes `STACK_TYPE` optional (override only).

**When to use:** When a single Docker image serves multiple upgrade paths. Detection runs once at startup before any template substitution.

**Detection logic (priority order):**
```bash
detect_stack_type() {
  if [ -f package.json ]; then
    # Priority: next > react-scripts (CRA) > vite+react > vite-react standalone
    if jq -e '.dependencies.next // .devDependencies.next' package.json > /dev/null 2>&1; then
      echo "nextjs"
    elif jq -e '."dependencies"."react-scripts" // ."devDependencies"."react-scripts"' package.json > /dev/null 2>&1; then
      echo "cra"
    elif jq -e '.dependencies.react // .devDependencies.react' package.json > /dev/null 2>&1; then
      echo "vite-react"
    else
      echo "unknown"
    fi
  else
    echo "unknown"
  fi
}

STACK_TYPE="${STACK_TYPE:-$(detect_stack_type)}"

if [ "$STACK_TYPE" = "unknown" ]; then
  echo "ERROR: Could not detect JS stack type. Set STACK_TYPE env var."
  exit 1
fi

# Drop the correct template set
envsubst < /skill/templates/${STACK_TYPE}/plan.md > .upgrade/plan.md
envsubst < /skill/templates/${STACK_TYPE}/checklist.yaml > .upgrade/checklist.yaml
cp /skill/templates/${STACK_TYPE}/CLAUDE.md .upgrade/CLAUDE.md
# ... etc
```

**Trade-offs:** Detection is fast (one `jq` parse). The `STACK_TYPE` env var override allows manual correction when detection is wrong. Keeps `docker run` ergonomics clean for the common case.

### Pattern 2: Template Variable Substitution (same as Laravel)

**What:** Templates use `${TARGET_VERSION}`, `${UPGRADE_DATE}`, `${STACK_TYPE}` as placeholders, substituted by `envsubst` in the entrypoint before the agent starts.

**When to use:** Any value that varies per run but should be baked into the agent's instructions. Survives context compaction because the substituted files live in `.upgrade/`.

**JS-specific variables:**
```bash
export TARGET_VERSION="${TARGET_NEXTJS:-${TARGET_REACT:-${TARGET_VITE:-latest}}}"
export UPGRADE_DATE=$(date -u +%Y-%m-%d)
export STACK_TYPE="$STACK_TYPE"
envsubst < /skill/templates/${STACK_TYPE}/plan.md > .upgrade/plan.md
```

**Trade-offs:** Each stack needs its own env key (`TARGET_NEXTJS`, `TARGET_REACT`, etc.) to map cleanly to the CLI registry. The entrypoint normalizes these to `TARGET_VERSION` before envsubst so all templates can use the same placeholder.

### Pattern 3: Three-File Memory System (identical to Laravel)

**What:** `plan.md`, `checklist.yaml`, `run-log.md` live in `.upgrade/` and are read by the agent on every start. This is the durable memory that survives context compaction and container restarts.

**When to use:** Always — no deviation from the playbook pattern. The JS agent's startup protocol mirrors Laravel exactly: read plan → find first incomplete checklist task → read run-log → read recon report → begin.

**Trade-offs:** None. This is the core resilience mechanism. Changing it would break the ralph-loop's completion detection, which relies on `checklist.yaml` status fields.

### Pattern 4: Verify Script Uniformity via npm Scripts

**What:** All three web JS stacks are expected to expose `npm run lint`, `npm run build`, `npm test` (or `npm run test`). The shared `verify-fast.sh` and `verify-full.sh` call these. Stack-specific behavior lives in `package.json`, not in the verify scripts.

**When to use:** This assumption holds for Next.js, CRA, and Vite+React. The agent is instructed to ensure these scripts exist (or create them) as part of the upgrade.

**Fast verify (JS):**
```bash
#!/bin/bash
set -e
echo "=== verify-fast ==="
echo "[1/3] TypeScript type check..."
npx tsc --noEmit 2>&1 || npm run type-check 2>&1
echo "[2/3] Lint..."
npm run lint 2>&1
echo "[3/3] Unit tests..."
npm test -- --watchAll=false 2>&1 || npm run test:unit 2>&1
echo "=== verify-fast PASSED ==="
```

**Full verify (JS):**
```bash
#!/bin/bash
set -e
echo "=== verify-full ==="
echo "[1/4] TypeScript type check..."
npx tsc --noEmit 2>&1
echo "[2/4] Lint..."
npm run lint 2>&1
echo "[3/4] All tests..."
npm test -- --watchAll=false --coverage 2>&1 || npm run test 2>&1
echo "[4/4] Production build..."
npm run build 2>&1
echo "[5/4] Security audit..."
npm audit --production 2>&1 || echo "(audit warnings — non-blocking)"
echo "=== verify-full PASSED ==="
```

**Trade-offs:** If a repo does not have `npm run lint` configured, verify-fast will fail immediately. The agent must add/fix these scripts as part of Phase 1 (or the template CLAUDE.md must instruct it to do so). This is acceptable — it forces good hygiene.

---

## Entrypoint Flow (node image)

```
[Start]
    |
    v
Validate env vars
(REPO_URL + one of TARGET_NEXTJS/TARGET_REACT/TARGET_VITE + auth)
    |
    v
Setup SSH key or GH_TOKEN credential helper
    |
    v
git clone $REPO_URL /workspace
    |
    v
Detect STACK_TYPE from package.json
(or use $STACK_TYPE env override)
    |
    v
Branch: check remote / create upgrade/{stack}-{version}[-{suffix}]
    |
    v
npm ci || npm install (best-effort, non-fatal)
    |
    v
Before-snapshots: npm ls --json -> /output/before-npm.json
                  node -v, npm -v -> /output/before-versions.txt
    |
    v
Baseline verify-full (non-fatal, output -> /output/baseline.log)
    |
    v
mkdir -p .upgrade/scripts
envsubst templates/{STACK_TYPE}/* -> .upgrade/
cp verify-fast.sh + verify-full.sh -> .upgrade/scripts/
    |
    v
Fetch official upgrade/migration docs
(e.g. nextjs.org/docs/upgrading, vitejs.dev/guide/migration)
-> .upgrade/{stack}-upgrade-guide.html (non-fatal)
    |
    v
recon.sh (JS-specific analysis) -> .upgrade/recon-report.md
    |
    v
exec ralph-loop.sh
```

**Key difference from Laravel:** The detect-and-select step between clone and branch creation. Laravel skips detection — `TARGET_LARAVEL` is mandatory. The node entrypoint inserts detection after clone so the branch name can incorporate the stack type (e.g., `upgrade/nextjs-15`).

---

## Data Flow

### Template Selection Flow

```
/skill/templates/
  nextjs/plan.md          ─┐
  cra/plan.md              ├── selected by STACK_TYPE
  vite-react/plan.md      ─┘
         |
         v (envsubst with TARGET_VERSION, UPGRADE_DATE, STACK_TYPE)
         |
.upgrade/plan.md          ← agent reads this on every start
.upgrade/checklist.yaml   ← ralph-loop reads this to decide restart
.upgrade/CLAUDE.md        ← agent's primary instruction set
.upgrade/run-log.md       ← append-only memory across sessions
.upgrade/changelog.md     ← becomes PR body
```

### Agent Run Loop

```
ralph-loop.sh
    |
    v
claude --dangerously-skip-permissions --max-turns $MAX_TURNS
    |
    v (agent reads .upgrade/*.md + .upgrade/checklist.yaml)
    |
    v
Phase N: edit files
    |
    v
.upgrade/scripts/verify-fast.sh    (after each change)
    |
    v
.upgrade/scripts/verify-full.sh    (before phase completion)
    |
    v
git commit "upgrade(phase-N): ..."
update checklist.yaml status: complete
update changelog.md
append run-log.md
    |
    v
Next phase (or exit 0 if all complete)
    |
    v
ralph-loop: check checklist for incomplete tasks
  - All complete -> write /output/result.json, push, create PR, exit 0
  - Incomplete + restarts < MAX -> restart claude
  - Incomplete + restarts >= MAX -> exit 1 (halted)
```

### After-Run Artifacts

```
/output/
  result.json              # outcome: success/incomplete, phase counts, elapsed
  status.json              # live status during run
  before-npm.json          # pre-upgrade npm packages
  after-npm.json           # post-upgrade npm packages
  before-versions.txt      # pre-upgrade Node/framework versions
  after-versions.txt       # post-upgrade versions
  baseline.log             # pre-upgrade verify output
  recon.log                # recon script stdout
  changelog.md             # agent changelog (PR body)
  run-log.md               # agent decision log
  checklist.yaml           # final phase statuses
  plan.md                  # upgrade plan used
  commits.log              # git log --oneline
  claude-run-*.jsonl       # raw stream-json per session
```

---

## How JS Differs from the Laravel Pattern

| Dimension | Laravel | Node (web JS) | React Native |
|-----------|---------|---------------|--------------|
| Stack detection | None (TARGET_LARAVEL required) | Auto from package.json in entrypoint | None (single stack per image) |
| Image base | php:8.4-cli-bookworm (multi-stage) | node:22-bookworm-slim | node:22-bookworm + JDK 17 + Android SDK |
| Templates | Single set in /skill/templates/ | Three sets; selected at launch by STACK_TYPE | Single set |
| Dependency install | composer install + npm ci | npm ci only | npm ci only |
| Env setup | cp .env.example + artisan key:generate | none (no .env equivalent for web JS) | none |
| Pre-run resource fetch | laravel.com/docs/{version}/upgrade | nextjs.org/docs/upgrading (etc.) | reactnative.dev/docs/upgrading |
| verify-fast | composer validate + route:list + tests | tsc + lint + unit tests | tsc + lint + jest unit tests |
| verify-full | above + migrate:fresh + npm build + audit | above + npm run build + audit | above + (optional) Android build |
| Post-run snapshot | composer show + npm ls | npm ls only | npm ls only |
| PR branch prefix | upgrade/laravel-{version} | upgrade/nextjs-{version} etc. | upgrade/react-native-{version} |
| CLI detection | reads composer.json | reads package.json | reads package.json (react-native dep) |

### Key Difference: CRA is a Migration, Not an Upgrade

CRA (Create React App / react-scripts) is unmaintained. The CRA agent does not upgrade CRA — it migrates the project to Vite. This means:

- The `cra` template's `plan.md` describes a migration plan (remove react-scripts, install vite, update config, fix imports)
- The branch is named `migrate/cra-to-vite` not `upgrade/cra-{version}`
- `verify-fast.sh` and `verify-full.sh` are the same shared scripts (they work post-migration)
- The CLI `branchPrefix` for CRA is `migrate/cra-to-vite` (fixed string, no version)

### Key Difference: React Native Needs Android SDK

The React Native image requires JDK 17 and Android SDK for full build verification. However, a full Android build takes 10-30 minutes and requires significant compute. The `verify-full.sh` for React Native conditionally runs the Android build only if `ANDROID_BUILD=true` is set:

```bash
# verify-full.sh (react-native)
if [ "${ANDROID_BUILD:-false}" = "true" ]; then
  echo "[5/5] Android build..."
  cd android && ./gradlew assembleRelease 2>&1
fi
```

By default, verification for React Native is: lint + TypeScript + jest. The Android build is opt-in.

---

## Component Boundaries (Shared vs Stack-Specific)

### Shared Across All JS Stacks (node image)

| Component | Location | Notes |
|-----------|----------|-------|
| Dockerfile | `stacks/node/Dockerfile` | Single file for all 3 web stacks |
| entrypoint.sh | `stacks/node/entrypoint.sh` | Detection logic lives here |
| ralph-loop.sh | `stacks/node/scripts/ralph-loop.sh` | Identical pattern to Laravel |
| stream-pretty.sh | `stacks/node/scripts/stream-pretty.sh` | Identical to Laravel version |
| verify-fast.sh | `stacks/node/scripts/verify-fast.sh` | JS-specific but shared across 3 stacks |
| verify-full.sh | `stacks/node/scripts/verify-full.sh` | JS-specific but shared across 3 stacks |
| recon.sh | `stacks/node/scripts/recon.sh` | JS-specific but shared across 3 stacks |

### Stack-Specific (per template subdirectory)

| Component | Location | Notes |
|-----------|----------|-------|
| CLAUDE.md | `stacks/node/templates/{stack}/CLAUDE.md` | Stack-specific agent instructions |
| plan.md | `stacks/node/templates/{stack}/plan.md` | Stack-specific upgrade phases |
| checklist.yaml | `stacks/node/templates/{stack}/checklist.yaml` | Stack-specific phase tasks |
| run-log.md | `stacks/node/templates/{stack}/run-log.md` | Template is identical; can share one |
| changelog.md | `stacks/node/templates/{stack}/changelog.md` | Template is identical; can share one |

### Separate (React Native image)

Everything in `stacks/react-native/` is separate — different Dockerfile, different scripts (RN-specific recon, conditional Android build), different templates.

---

## JS Recon Script Design

The JS recon script differs substantially from Laravel's. It must detect:

1. **Framework and version** — `next`, `react`, `vite`, `react-scripts` from package.json
2. **TypeScript** — presence of `tsconfig.json`, `typescript` in deps
3. **Test runner** — `jest`, `vitest`, `@testing-library/react` from package.json
4. **CSS tooling** — Tailwind, CSS Modules, styled-components, Emotion
5. **Build output** — `dist/`, `.next/`, `build/` existence
6. **Dependency counts** — total deps, major outdated packages
7. **Import patterns** — check for deprecated APIs (e.g., Next.js Pages vs App Router usage)

```bash
# recon.sh excerpt (JS)
echo "## Framework Detection" >> "$REPORT"
NEXT_VERSION=$(jq -r '.dependencies.next // .devDependencies.next // "not installed"' package.json)
REACT_VERSION=$(jq -r '.dependencies.react // "not installed"' package.json)
VITE_VERSION=$(jq -r '.devDependencies.vite // "not installed"' package.json)
echo "- Next.js: $NEXT_VERSION" >> "$REPORT"
echo "- React: $REACT_VERSION" >> "$REPORT"
echo "- Vite: $VITE_VERSION" >> "$REPORT"

echo "## TypeScript" >> "$REPORT"
if [ -f tsconfig.json ]; then
  echo "- TypeScript: Yes (tsconfig.json found)" >> "$REPORT"
  TS_STRICT=$(jq -r '.compilerOptions.strict // false' tsconfig.json)
  echo "- Strict mode: $TS_STRICT" >> "$REPORT"
else
  echo "- TypeScript: No" >> "$REPORT"
fi

echo "## Test Runner" >> "$REPORT"
if jq -e '.devDependencies.vitest // .dependencies.vitest' package.json > /dev/null 2>&1; then
  echo "- Test runner: Vitest" >> "$REPORT"
elif jq -e '.devDependencies.jest // .dependencies.jest' package.json > /dev/null 2>&1; then
  echo "- Test runner: Jest" >> "$REPORT"
else
  echo "- Test runner: None detected" >> "$REPORT"
fi
```

---

## Build Order Implications

The following dependencies between components affect implementation order:

```
1. stacks/node/Dockerfile
      |
      | (image must exist before testing entrypoint)
      v
2. stacks/node/entrypoint.sh + scripts/recon.sh + scripts/verify-*.sh + scripts/ralph-loop.sh
      |
      | (scripts must work before templates are useful)
      v
3. stacks/node/templates/nextjs/   (highest-value stack, build first)
      |
      v
4. stacks/node/templates/vite-react/
      |
      v
5. stacks/node/templates/cra/      (migration, different from upgrades)
      |
      | (CLI changes needed to wire up docker run calls)
      v
6. cli/src/stacks.js               (add nextjs, vite-react, cra, react-native entries)
      |
      v
7. stacks/react-native/Dockerfile  (large image, build last — slowest CI)
      |
      v
8. stacks/react-native/ entrypoint + scripts + templates
      |
      v
9. .github/workflows/release.yml   (add node + react-native to matrix)
```

**Rationale for this order:**
- Dockerfile first because all other components depend on it being testable
- Next.js templates before CRA/Vite because Next.js is the most common upgrade case and validates the shared script assumptions
- CLI registry last (before RN) because it wires everything together and is best validated against working images
- React Native last because its image is slow to build and the pattern is proven by then

---

## Anti-Patterns

### Anti-Pattern 1: One Image Per Web JS Stack

**What people do:** Create `stacks/nextjs/`, `stacks/cra/`, `stacks/vite-react/` as separate Docker images, each with their own Dockerfile.

**Why it's wrong:** All three stacks need identical system dependencies: Node 22, npm, gh CLI, Claude Code, git, ssh-client, jq, envsubst. Three near-identical 500MB images bloat CI build time and maintenance overhead. The only real difference is the templates dropped at runtime.

**Do this instead:** One `stacks/node/` image with three template subdirectories. The entrypoint selects the right one. Three CI matrix entries still produce three logical agents, but they all build from the same Dockerfile.

### Anti-Pattern 2: Stack Detection in CLI Instead of Entrypoint

**What people do:** Detect stack type in `cli/src/github.js` during repo discovery and pass `STACK_TYPE` as a required env var to every docker run.

**Why it's wrong:** It forces the CLI to do accurate package.json parsing for every discovered repo before the user queues a run. Inaccurate detection at the CLI level means wrong image selected. The entrypoint has the actual `package.json` after clone — detection there is authoritative.

**Do this instead:** CLI does best-effort detection for UX (showing the user what it thinks the stack is), but passes `STACK_TYPE` as an overridable hint. The entrypoint re-detects from the cloned `package.json` and overrides only if `STACK_TYPE` is explicitly set by the user.

### Anti-Pattern 3: Running Android Builds by Default in React Native

**What people do:** Include `cd android && ./gradlew assembleRelease` unconditionally in `verify-full.sh` for React Native.

**Why it's wrong:** A full Android build takes 10-30 minutes and requires Gradle cache warmup. It turns a ~5-minute upgrade verification into a 35-minute job and may fail due to keystore/signing issues unrelated to the upgrade.

**Do this instead:** Gate the Android build behind `ANDROID_BUILD=true`. Default verification is lint + TypeScript + jest. Document that users should set `ANDROID_BUILD=true` for final pre-PR verification.

### Anti-Pattern 4: Separate ralph-loop.sh per Stack

**What people do:** Copy and customize ralph-loop.sh for each stack because the post-run snapshots differ (composer show vs npm ls).

**Why it's wrong:** The ralph-loop's core logic (restart on incomplete checklist, write status.json, write result.json) is identical across all stacks. Duplicate files diverge over time.

**Do this instead:** Keep one `ralph-loop.sh` per image (laravel, node, react-native). The post-run snapshot commands differ by image, not by sub-stack. Within the node image, `npm ls` covers all three web JS stacks uniformly.

---

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| GitHub (clone) | SSH key (GIT_SSH_KEY_B64) or HTTPS (GH_TOKEN) | Same pattern as Laravel |
| GitHub (PR creation) | `gh pr create` via GH_TOKEN | Same as Laravel; PR body = changelog.md |
| nextjs.org upgrade docs | curl fetch at entrypoint startup | Non-fatal if unreachable |
| reactnative.dev upgrade docs | curl fetch at entrypoint startup | Non-fatal if unreachable |
| Anthropic API / Claude Max | ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN | Same as Laravel |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| entrypoint.sh -> ralph-loop.sh | exec (process replacement) | entrypoint never returns; ralph owns exit code |
| ralph-loop.sh -> claude | subprocess with stream-json output | stdout piped through stream-pretty.sh for logs |
| claude agent -> verify scripts | shell exec of .upgrade/scripts/verify-fast.sh | Agent has shell access via Claude Code permissions |
| ralph-loop.sh -> /output/ | file writes | Monitoring reads status.json; CI reads result.json |
| CLI -> Docker | docker run with env vars | All config passed as env; no bind mounts required except /output |

---

## Sources

- Direct analysis of `stacks/laravel/Dockerfile`, `entrypoint.sh`, `scripts/`, `templates/` (HIGH confidence)
- `cli/src/stacks.js` — confirmed stack registry pattern (HIGH confidence)
- `.planning/PROJECT.md` — confirmed architectural decisions (shared node image, separate RN image, auto-detection) (HIGH confidence)
- `CLAUDE.md` (project root) — Nayeem Zen Playbook v8 pattern documentation (HIGH confidence)

---
*Architecture research for: JS upgrade agents (stack-upgrade monorepo)*
*Researched: 2026-03-01*
