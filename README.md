# Laravel Upgrade Agent

Disposable Docker image that runs Claude Code autonomously to upgrade any Laravel application.

## How It Works

1. Clones your repo, creates an `upgrade/laravel-{version}` branch
2. Runs baseline verification (tests, routes, build)
3. Drops upgrade plan, checklist, and agent guidelines into the repo
4. Launches Claude Code with full permissions via a restart loop ("Ralph loop")
5. Claude works through 6 upgrade phases, committing after each
6. Pushes the branch when done; artifacts copied to `/output`

## Usage

### With Claude Max (recommended)

Generate a token with `claude setup-token`, then:

```bash
docker build -t laravel-upgrade-agent .

docker run --rm \
  -e REPO_URL=git@github.com:org/repo.git \
  -e TARGET_LARAVEL=13 \
  -e CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN \
  -e GIT_SSH_KEY_B64=$(base64 < ~/.ssh/deploy_key) \
  -v ./output:/output \
  laravel-upgrade-agent
```

### With Anthropic API Key

```bash
docker run --rm \
  -e REPO_URL=git@github.com:org/repo.git \
  -e TARGET_LARAVEL=13 \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  -e GIT_SSH_KEY_B64=$(base64 < ~/.ssh/deploy_key) \
  -v ./output:/output \
  laravel-upgrade-agent
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `REPO_URL` | Yes | — | Git clone URL (SSH) |
| `TARGET_LARAVEL` | Yes | — | Target major version (e.g., `13`) |
| `CLAUDE_CODE_OAUTH_TOKEN` | One of | — | Claude Max token (from `claude setup-token`) |
| `ANTHROPIC_API_KEY` | One of | — | Anthropic API key (from console.anthropic.com) |
| `GIT_SSH_KEY_B64` | Yes | — | Base64-encoded deploy key |
| `GIT_PUSH` | No | `true` | Push branch on completion |
| `UPGRADE_FILAMENT` | No | `true` | Include Filament upgrade phase |
| `MAX_RESTARTS` | No | `5` | Max Claude Code restarts |

## Upgrade Phases

1. **Core Framework** — `laravel/framework` to target version
2. **First-Party Packages** — Horizon, Telescope, Sanctum, etc.
3. **Filament + Livewire** — major version bumps
4. **Third-Party Composer** — remaining packages
5. **NPM + Frontend** — deps + build
6. **Config Drift** — reconcile against stubs

## Output

After a run, the `/output` volume contains:

- `baseline.log` — pre-upgrade test results
- `run-log.md` — agent decision log
- `checklist.yaml` — final phase statuses
- `plan.md` — the upgrade plan used
- `commits.log` — all commits on the upgrade branch

## Security

- Use a **repo-scoped deploy key**, not your personal SSH key
- API keys/tokens are passed as env vars, never baked into the image
- Container is ephemeral — destroyed after run
- Review the upgrade branch before merging

## Ralph Loop

The agent runs inside a restart loop. If Claude Code exits before the checklist is complete, it restarts with full context (reads `run-log.md` and `checklist.yaml` on startup). Max restarts default to 5.
