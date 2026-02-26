# CLAUDE.md — Laravel Upgrade Agent (Dev)

Instructions for developing the laravel-upgrade-agent itself (not for the agent running inside Docker).

## What This Project Is

A disposable Docker image that runs Claude Code autonomously to upgrade any Laravel app. It clones a repo, creates an `upgrade/laravel-{version}` branch, works through 7 phases, commits per phase, and pushes. Optionally creates a PR with a generated changelog.

## Architecture

```
entrypoint.sh          # Clone repo, setup branch, install deps, recon, drop templates, launch ralph loop
scripts/ralph-loop.sh  # Restart loop — relaunches Claude Code if it exits before checklist complete
scripts/recon.sh       # Pre-run repo analysis — produces .upgrade/recon-report.md
scripts/verify-fast.sh # Quick check: composer validate + route:list + tests
scripts/verify-full.sh # Full check: above + migrate:fresh + npm build + audits
scripts/stream-pretty.sh # Prettifies Claude Code stream-json output for logs
kickoff-prompt.txt     # Initial prompt sent to Claude Code inside the container
Dockerfile             # PHP 8.4, Node 22, Composer 2, gh CLI, Claude Code CLI, non-root user
templates/
  CLAUDE.md            # Dropped into .upgrade/ — agent instructions (NOT this file)
  plan.md              # Dropped into .upgrade/ — 6-phase upgrade plan (uses envsubst)
  checklist.yaml       # Dropped into .upgrade/ — phase tracking (uses envsubst)
  run-log.md           # Dropped into .upgrade/ — agent decision log
  changelog.md         # Dropped into .upgrade/ — agent-maintained changelog (used as PR body)
```

### Workspace Layout (inside container)

All upgrade artifacts live in `.upgrade/` to avoid polluting the target repo:

```
/workspace/
  .upgrade/
    CLAUDE.md              # Agent instructions
    plan.md                # Upgrade plan
    checklist.yaml         # Phase tracking
    run-log.md             # Decision log
    changelog.md           # Per-phase changelog (becomes PR body)
    recon-report.md        # Pre-run repo analysis
    laravel-upgrade-guide.html  # Official upgrade docs (fetched at startup)
    scripts/
      verify-fast.sh       # Quick verification
      verify-full.sh       # Full verification
  CLAUDE.md                # Original project CLAUDE.md (preserved, not overwritten)
  ...                      # Target repo files
```

## Design Pattern: Long-Running Agent (Nayeem Zen Playbook v8)

This project implements the **Long-Running Agents Playbook** pattern. Key principles:

### Core Loop: PLAN -> BUILD -> VERIFY -> AUDIT -> EVOLVE

### Three-File Memory System

The agent's durable memory survives context compaction and session restarts:

| File | Purpose | Location |
|------|---------|----------|
| `plan.md` | Blueprint — phases, constraints, verification strategy | Template: `templates/plan.md` -> dropped into `.upgrade/` |
| `checklist.yaml` | Executable work items with acceptance criteria and status | Template: `templates/checklist.yaml` -> dropped into `.upgrade/` |
| `run-log.md` | Append-only ops log: decisions, evidence, failures, fixes | Template: `templates/run-log.md` -> dropped into `.upgrade/` |

### Execution Loop (what the agent does per phase)

1. Pick the next `not_started` task in `checklist.yaml`
2. Re-read `plan.md` and relevant code
3. Make the smallest change that moves the task forward
4. Run the fastest verification that can catch the likely failure (`verify-fast.sh`)
5. Commit a checkpoint (one commit per phase)
6. Update `checklist.yaml` status, `changelog.md`, and append to `run-log.md`
7. Repeat

### Key Patterns Applied

- **Make "done" measurable** — each phase has acceptance criteria the agent proves with `verify-fast.sh` / `verify-full.sh`
- **Keep durable memory outside chat** — the three-file system above
- **Keep the verification loop cheap** — `verify-fast.sh` (seconds) runs after every change; `verify-full.sh` (minutes) runs at phase completion
- **Checkpoint constantly** — one commit per phase, reversible steps
- **Loop breaker** — after 3 failed attempts on the same error, log failure, mark phase `failed`, move on (prevents infinite loops)
- **Ralph loop** — restart harness that relaunches Claude Code if it exits before checklist is complete (handles context exhaustion gracefully)
- **Recon before action** — `scripts/recon.sh` maps the repo (package usage, component counts, test shape) before the agent starts
- **Self-evolve** — after every run, review `run-log.md` for patterns that should become template/constraint changes

### Steering Messages (for manual intervention during a run)

If you need to steer the agent mid-run (via Docker exec or modifying files):
- "Stop. You are changing files outside scope. Re-read `.upgrade/plan.md`, then continue with the next checklist task only."
- "You are stuck in retries. Write a short diagnosis in `.upgrade/run-log.md`, then change approach."
- "Commit a checkpoint now. Then run the fast loop and paste only the summary."
- "Do the smallest safe step next. No refactors. One file. One test. One commit."

## Key Concepts

- **Templates** use `${TARGET_LARAVEL}` and `${UPGRADE_DATE}` — substituted by `envsubst` in entrypoint.sh
- **Ralph loop** (`scripts/ralph-loop.sh`) restarts Claude Code up to `MAX_RESTARTS` times if checklist has incomplete tasks
- **Branch handling** (`entrypoint.sh`): checks if remote branch exists first — if yes, checks out and rebases; if no, creates fresh. Supports `BRANCH_SUFFIX` for repeat runs.
- **One commit per phase** — no intermediate commits within a phase
- **Push + PR** — push happens at end of ralph-loop.sh (controlled by `GIT_PUSH`). If `GH_TOKEN` is set, a PR is auto-created using `.upgrade/changelog.md` as the body.
- **Structured exit** — exit 0 = all complete, exit 1 = incomplete. `/output/result.json` has outcome summary.
- **Status monitoring** — `/output/status.json` is updated throughout the run for external monitoring.
- **Dependency snapshots** — before/after JSON snapshots of composer and npm packages saved to `/output/` for diff-based review.
- **Recon** — `scripts/recon.sh` produces `.upgrade/recon-report.md` with package usage analysis, component counts, test suite shape.
- **Upgrade guide** — official Laravel upgrade docs fetched and saved to `.upgrade/laravel-upgrade-guide.html`.
- **No CLAUDE.md overwrite** — upgrade instructions go to `.upgrade/CLAUDE.md`; the target repo's own `CLAUDE.md` is preserved.

## Upgrade Philosophy (templates/CLAUDE.md + templates/plan.md)

These files define what the agent does inside the container:

- **Upgrade everything to latest major versions** — Filament v4/v5, Tailwind v4, etc. Code changes for new APIs are expected.
- **Never change application behaviour** — refactoring for package API changes is fine, changing what the code does is not.
- **Skip unused packages** — if not imported/used anywhere, remove instead of upgrading.
- **7 phases:** Core Framework > First-Party > Filament+Livewire > Third-Party Composer > NPM+Frontend > Config Drift+README > PHP Version

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `REPO_URL` | Yes | — | SSH clone URL |
| `TARGET_LARAVEL` | Yes | — | Target major version (e.g., `12`, `13`) |
| `CLAUDE_CODE_OAUTH_TOKEN` | One of | — | Claude Max token |
| `ANTHROPIC_API_KEY` | One of | — | Anthropic API key |
| `GIT_SSH_KEY_B64` | Yes | — | Base64-encoded deploy key |
| `GIT_PUSH` | No | `true` | Push branch on completion |
| `GH_TOKEN` | No | — | GitHub token for auto PR creation (skip if empty) |
| `BRANCH_SUFFIX` | No | — | Append to branch name (e.g., `2026-02-26` → `upgrade/laravel-12-2026-02-26`) |
| `MAX_RESTARTS` | No | `5` | Max Claude Code restart attempts |
| `MAX_TURNS` | No | `200` | Max agentic turns per Claude Code session |

## Output Artifacts

After a run, `/output/` contains:

| File | Description |
|------|-------------|
| `result.json` | Structured outcome: success/incomplete, phase counts, elapsed time |
| `status.json` | Last status update (for monitoring during run) |
| `before-composer.json` | Pre-upgrade composer packages |
| `after-composer.json` | Post-upgrade composer packages |
| `before-npm.json` | Pre-upgrade npm packages |
| `after-npm.json` | Post-upgrade npm packages |
| `before-versions.txt` | Pre-upgrade Laravel/PHP versions |
| `after-versions.txt` | Post-upgrade Laravel/PHP versions |
| `changelog.md` | Agent-maintained changelog (also used as PR body) |
| `run-log.md` | Agent decision log |
| `checklist.yaml` | Final phase statuses |
| `plan.md` | Upgrade plan used |
| `recon.log` | Recon script output |
| `baseline.log` | Pre-upgrade verification output |
| `commits.log` | Git log of commits made |
| `claude-run-*.jsonl` | Raw Claude Code stream output per session |

## Dev Workflow

```bash
# Build
docker build -t laravel-upgrade-agent .

# Test run (no push)
docker run --rm \
  -e REPO_URL=git@github.com:org/repo.git \
  -e TARGET_LARAVEL=12 \
  -e GIT_PUSH=false \
  -e CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN \
  -e GIT_SSH_KEY_B64=$(base64 < ~/.ssh/deploy_key) \
  -v ./output:/output \
  laravel-upgrade-agent

# Test run with branch suffix and auto PR
docker run --rm \
  -e REPO_URL=git@github.com:org/repo.git \
  -e TARGET_LARAVEL=12 \
  -e BRANCH_SUFFIX=$(date +%Y-%m-%d) \
  -e GH_TOKEN=$GH_TOKEN \
  -e CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN \
  -e GIT_SSH_KEY_B64=$(base64 < ~/.ssh/deploy_key) \
  -v ./output:/output \
  laravel-upgrade-agent

# Check output
cat output/result.json
cat output/changelog.md
cat output/run-log.md
cat output/checklist.yaml
cat output/commits.log

# Compare dependency changes
diff <(jq -r '.installed[] | .name' output/before-composer.json | sort) \
     <(jq -r '.installed[] | .name' output/after-composer.json | sort)
```

## Recent Changes

- **`.upgrade/` folder** — all upgrade artifacts now live in `.upgrade/` instead of the workspace root; target repo's `CLAUDE.md` is preserved
- **Recon phase** — `scripts/recon.sh` maps package usage, component counts, and test shape before the agent starts
- **Changelog** — agent maintains `.upgrade/changelog.md` per phase; used as PR body
- **Upgrade guide fetch** — official Laravel upgrade docs fetched to `.upgrade/laravel-upgrade-guide.html`
- **Dependency snapshots** — before/after JSON snapshots for diff-based review
- **Structured exit** — exit 0/1 with `/output/result.json` summary
- **Status monitoring** — `/output/status.json` updated throughout for external monitoring
- **Auto PR** — `gh pr create` when `GH_TOKEN` is set
- **Branch suffix** — `BRANCH_SUFFIX` env var for repeat runs without collision
- **Branch reuse** — entrypoint.sh checks for existing remote branch and rebases instead of blindly creating
- **Upgrade philosophy** — "never modify business logic" replaced with "never change application behaviour" so major package upgrades proceed with required code changes
- **Unused package removal** — agent removes packages not imported anywhere instead of upgrading them
- **Flux/flux-pro awareness** — Phase 3 checks for livewire/flux and livewire/flux-pro

## Commit Convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for automatic semantic versioning via `semantic-release`. Every commit to `main` is analyzed to determine if a release is needed.

**Format:** `<type>(<scope>): <description>`

| Type | When | Release |
|------|------|---------|
| `fix` | Bug fixes, correcting broken behavior | Patch (1.0.0 → 1.0.1) |
| `feat` | New features, new capabilities | Minor (1.0.0 → 1.1.0) |
| `feat!` or `BREAKING CHANGE:` in body | Breaking changes (removed env vars, changed defaults, incompatible template changes) | Major (1.0.0 → 2.0.0) |
| `docs` | Documentation only | No release |
| `chore` | Maintenance, deps, CI config | No release |
| `ci` | CI/CD workflow changes | No release |
| `refactor` | Code restructuring, no behavior change | No release |
| `test` | Adding or fixing tests | No release |

**Scopes** (optional but encouraged): `entrypoint`, `ralph`, `recon`, `templates`, `dockerfile`, `ci`

**Examples:**
```
fix(ralph): handle missing checklist.yaml on restart
feat(entrypoint): add BRANCH_SUFFIX env var for repeat runs
feat!: move all artifacts to .upgrade/ folder
docs: update README with new output artifacts
chore(dockerfile): bump Node to 22.x
ci: add semantic-release workflow
```

## File Editing Rules

- `templates/` files are what the agent sees inside the container — changes here affect agent behaviour
- `entrypoint.sh` and `scripts/` are the orchestration layer — changes here affect the run lifecycle
- `Dockerfile` rarely needs changes unless adding system deps or upgrading Claude Code
- Always test changes with `GIT_PUSH=false` first
