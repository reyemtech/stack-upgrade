# CLAUDE.md — Laravel Upgrade Agent (Dev)

Instructions for developing the laravel-upgrade-agent itself (not for the agent running inside Docker).

## What This Project Is

A disposable Docker image that runs Claude Code autonomously to upgrade any Laravel app. It clones a repo, creates an `upgrade/laravel-{version}` branch, works through 6 phases, commits per phase, and pushes.

## Architecture

```
entrypoint.sh          # Clone repo, setup branch, install deps, drop templates, launch ralph loop
scripts/ralph-loop.sh  # Restart loop — relaunches Claude Code if it exits before checklist complete
scripts/verify-fast.sh # Quick check: composer validate + route:list + tests
scripts/verify-full.sh # Full check: above + migrate:fresh + npm build + audits
scripts/stream-pretty.sh # Prettifies Claude Code stream-json output for logs
kickoff-prompt.txt     # Initial prompt sent to Claude Code inside the container
Dockerfile             # PHP 8.4, Node 22, Composer 2, Claude Code CLI, non-root user
templates/
  CLAUDE.md            # Dropped into target repo — agent instructions (NOT this file)
  plan.md              # Dropped into target repo — 6-phase upgrade plan (uses envsubst)
  checklist.yaml       # Dropped into target repo — phase tracking (uses envsubst)
  run-log.md           # Dropped into target repo — agent decision log
```

## Design Pattern: Long-Running Agent (Nayeem Zen Playbook v8)

This project implements the **Long-Running Agents Playbook** pattern. Key principles:

### Core Loop: PLAN -> BUILD -> VERIFY -> AUDIT -> EVOLVE

### Three-File Memory System

The agent's durable memory survives context compaction and session restarts:

| File | Purpose | Location |
|------|---------|----------|
| `plan.md` | Blueprint — phases, constraints, verification strategy | Template: `templates/plan.md` -> dropped into `/workspace` |
| `checklist.yaml` | Executable work items with acceptance criteria and status | Template: `templates/checklist.yaml` -> dropped into `/workspace` |
| `run-log.md` | Append-only ops log: decisions, evidence, failures, fixes | Template: `templates/run-log.md` -> dropped into `/workspace` |

### Execution Loop (what the agent does per phase)

1. Pick the next `not_started` task in `checklist.yaml`
2. Re-read `plan.md` and relevant code
3. Make the smallest change that moves the task forward
4. Run the fastest verification that can catch the likely failure (`verify-fast.sh`)
5. Commit a checkpoint (one commit per phase)
6. Update `checklist.yaml` status and append to `run-log.md`
7. Repeat

### Key Patterns Applied

- **Make "done" measurable** — each phase has acceptance criteria the agent proves with `verify-fast.sh` / `verify-full.sh`
- **Keep durable memory outside chat** — the three-file system above
- **Keep the verification loop cheap** — `verify-fast.sh` (seconds) runs after every change; `verify-full.sh` (minutes) runs at phase completion
- **Checkpoint constantly** — one commit per phase, reversible steps
- **Loop breaker** — after 3 failed attempts on the same error, log failure, mark phase `failed`, move on (prevents infinite loops)
- **Ralph loop** — restart harness that relaunches Claude Code if it exits before checklist is complete (handles context exhaustion gracefully)
- **Self-evolve** — after every run, review `run-log.md` for patterns that should become template/constraint changes

### Steering Messages (for manual intervention during a run)

If you need to steer the agent mid-run (via Docker exec or modifying files):
- "Stop. You are changing files outside scope. Re-read `plan.md`, then continue with the next checklist task only."
- "You are stuck in retries. Write a short diagnosis in `run-log.md`, then change approach."
- "Commit a checkpoint now. Then run the fast loop and paste only the summary."
- "Do the smallest safe step next. No refactors. One file. One test. One commit."

## Key Concepts

- **Templates** use `${TARGET_LARAVEL}` and `${UPGRADE_DATE}` — substituted by `envsubst` in entrypoint.sh
- **Ralph loop** (`scripts/ralph-loop.sh`) restarts Claude Code up to `MAX_RESTARTS` times if checklist has incomplete tasks
- **Branch handling** (`entrypoint.sh`): checks if remote branch exists first — if yes, checks out and rebases; if no, creates fresh
- **One commit per phase** — no intermediate commits within a phase
- **Push** happens at the end of ralph-loop.sh (controlled by `GIT_PUSH` env var)

## Upgrade Philosophy (templates/CLAUDE.md + templates/plan.md)

These files define what the agent does inside the container:

- **Upgrade everything to latest major versions** — Filament v4/v5, Tailwind v4, etc. Code changes for new APIs are expected.
- **Never change application behaviour** — refactoring for package API changes is fine, changing what the code does is not.
- **Skip unused packages** — if not imported/used anywhere, remove instead of upgrading.
- **6 phases:** Core Framework > First-Party > Filament+Livewire > Third-Party Composer > NPM+Frontend > Config Drift

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `REPO_URL` | Yes | — | SSH clone URL |
| `TARGET_LARAVEL` | Yes | — | Target major version (e.g., `12`, `13`) |
| `CLAUDE_CODE_OAUTH_TOKEN` | One of | — | Claude Max token |
| `ANTHROPIC_API_KEY` | One of | — | Anthropic API key |
| `GIT_SSH_KEY_B64` | Yes | — | Base64-encoded deploy key |
| `GIT_PUSH` | No | `true` | Push branch on completion |
| `MAX_RESTARTS` | No | `5` | Max Claude Code restart attempts |
| `MAX_TURNS` | No | `200` | Max agentic turns per Claude Code session |

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

# Check output
cat output/run-log.md
cat output/checklist.yaml
cat output/commits.log
```

## Recent Changes

- **Branch reuse** — entrypoint.sh now checks for existing remote branch and rebases instead of blindly creating (avoids non-fast-forward push failures)
- **Upgrade philosophy** — "never modify business logic" replaced with "never change application behaviour" so major package upgrades (Filament v4, Tailwind v4) proceed with required code changes
- **Unused package removal** — agent removes packages not imported anywhere instead of upgrading them
- **Flux/flux-pro awareness** — Phase 3 checks for livewire/flux and livewire/flux-pro

## File Editing Rules

- `templates/` files are what the agent sees inside the container — changes here affect agent behaviour
- `entrypoint.sh` and `scripts/` are the orchestration layer — changes here affect the run lifecycle
- `Dockerfile` rarely needs changes unless adding system deps or upgrading Claude Code
- Always test changes with `GIT_PUSH=false` first
