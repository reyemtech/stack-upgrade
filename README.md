# Laravel Upgrade Agent

[![Release](https://img.shields.io/github/v/release/reyemtech/laravel-upgrade-agent?sort=semver)](https://github.com/reyemtech/laravel-upgrade-agent/releases)
[![Build](https://github.com/reyemtech/laravel-upgrade-agent/actions/workflows/release.yml/badge.svg)](https://github.com/reyemtech/laravel-upgrade-agent/actions/workflows/release.yml)
[![License: BSL 1.1](https://img.shields.io/badge/License-BSL_1.1-yellow.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/ghcr.io-image-blue)](https://github.com/reyemtech/laravel-upgrade-agent/pkgs/container/laravel-upgrade-agent)

Disposable Docker image that runs [Claude Code](https://docs.anthropic.com/en/docs/claude-code) autonomously to upgrade any Laravel application. Point it at a repo, tell it the target version, and it produces an upgrade branch with one commit per phase.

**Multi-arch:** `linux/amd64` and `linux/arm64` — runs on any major cloud/k8s provider.

## Quick Start

### Pull from GHCR (recommended)

```bash
docker run --rm \
  -e REPO_URL=git@github.com:your-org/your-app.git \
  -e TARGET_LARAVEL=12 \
  -e CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN \
  -e GIT_SSH_KEY_B64=$(base64 < ~/.ssh/deploy_key) \
  -v ./output:/output \
  ghcr.io/reyemtech/laravel-upgrade-agent:latest
```

### Build locally

```bash
docker build -t laravel-upgrade-agent .

docker run --rm \
  -e REPO_URL=git@github.com:your-org/your-app.git \
  -e TARGET_LARAVEL=12 \
  -e CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN \
  -e GIT_SSH_KEY_B64=$(base64 < ~/.ssh/deploy_key) \
  -v ./output:/output \
  laravel-upgrade-agent
```

## How It Works

1. Clones your repo, creates an `upgrade/laravel-{version}` branch
2. Installs dependencies, runs baseline verification
3. Runs **recon** — analyzes package usage, component counts, test suite shape
4. Fetches the official Laravel upgrade guide for the target version
5. Launches Claude Code inside a restart loop ("Ralph loop")
6. Claude works through **7 upgrade phases**, committing after each
7. Captures before/after dependency snapshots for review
8. Pushes the branch (optionally creates a PR with a generated changelog)
9. Writes structured results to `/output`

## Upgrade Phases

| Phase | What it does |
|-------|-------------|
| 1. Core Framework | `laravel/framework` to target version, fix breaking changes |
| 2. First-Party Packages | Horizon, Telescope, Sanctum, Breeze, Pennant, etc. |
| 3. Filament + Livewire | Major version bumps (Filament v4/v5, Flux) |
| 4. Third-Party Composer | Remaining Composer packages |
| 5. NPM + Frontend | Tailwind v4, Vite, build tooling |
| 6. Config Drift | Reconcile config files against latest Laravel stubs |
| 7. PHP Version | Bump PHP constraint to latest compatible version |

Unused packages are **removed** instead of upgraded. Each phase runs verification before committing.

## Authentication

You need **one** of:

### Claude Max (recommended)

Generate a token with `claude setup-token`, then pass `CLAUDE_CODE_OAUTH_TOKEN`.

### Anthropic API Key

Pass `ANTHROPIC_API_KEY` from [console.anthropic.com](https://console.anthropic.com).

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `REPO_URL` | Yes | — | Git clone URL (SSH) |
| `TARGET_LARAVEL` | Yes | — | Target major version (e.g., `12`, `13`) |
| `CLAUDE_CODE_OAUTH_TOKEN` | One of | — | Claude Max token |
| `ANTHROPIC_API_KEY` | One of | — | Anthropic API key |
| `GIT_SSH_KEY_B64` | Yes | — | Base64-encoded deploy key |
| `GIT_PUSH` | No | `true` | Push branch on completion |
| `GH_TOKEN` | No | — | GitHub token — creates a PR with changelog as body |
| `BRANCH_SUFFIX` | No | — | Append to branch name (e.g., `2026-02-26` -> `upgrade/laravel-12-2026-02-26`) |
| `MAX_RESTARTS` | No | `5` | Max Claude Code restart attempts |
| `MAX_TURNS` | No | `200` | Max agentic turns per Claude Code session |

## Output

After a run, the `/output` volume contains:

| File | Description |
|------|-------------|
| `result.json` | Structured outcome — `success` or `incomplete`, phase counts, elapsed time |
| `status.json` | Last status update (poll this for monitoring) |
| `changelog.md` | Agent-maintained changelog (also used as PR body) |
| `before-composer.json` | Pre-upgrade Composer packages |
| `after-composer.json` | Post-upgrade Composer packages |
| `before-npm.json` / `after-npm.json` | Pre/post NPM packages |
| `before-versions.txt` / `after-versions.txt` | Pre/post Laravel/PHP versions |
| `run-log.md` | Agent decision log |
| `checklist.yaml` | Final phase statuses |
| `commits.log` | Git log of the upgrade branch |
| `baseline.log` | Pre-upgrade verification output |
| `recon.log` | Repo analysis output |

### Monitoring a running container

```bash
# Watch status
watch -n5 cat output/status.json

# Check result when done
cat output/result.json
# {"outcome":"success","exit_code":0,"total_phases":7,"completed":7,"failed":0,...}

# Compare dependency changes
diff <(jq -r '.installed[].name' output/before-composer.json | sort) \
     <(jq -r '.installed[].name' output/after-composer.json | sort)
```

## Advanced Usage

### Auto-create PR

Pass a GitHub token to automatically create a pull request with the changelog as the body:

```bash
docker run --rm \
  -e REPO_URL=git@github.com:your-org/your-app.git \
  -e TARGET_LARAVEL=12 \
  -e GH_TOKEN=$GH_TOKEN \
  -e CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN \
  -e GIT_SSH_KEY_B64=$(base64 < ~/.ssh/deploy_key) \
  -v ./output:/output \
  ghcr.io/reyemtech/laravel-upgrade-agent:latest
```

### Repeat runs (avoid branch collision)

```bash
docker run --rm \
  -e REPO_URL=git@github.com:your-org/your-app.git \
  -e TARGET_LARAVEL=12 \
  -e BRANCH_SUFFIX=$(date +%Y-%m-%d) \
  -e CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN \
  -e GIT_SSH_KEY_B64=$(base64 < ~/.ssh/deploy_key) \
  -v ./output:/output \
  ghcr.io/reyemtech/laravel-upgrade-agent:latest
```

### Dry run (no push)

```bash
docker run --rm \
  -e REPO_URL=git@github.com:your-org/your-app.git \
  -e TARGET_LARAVEL=12 \
  -e GIT_PUSH=false \
  -e CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN \
  -e GIT_SSH_KEY_B64=$(base64 < ~/.ssh/deploy_key) \
  -v ./output:/output \
  ghcr.io/reyemtech/laravel-upgrade-agent:latest
```

### Run on Kubernetes

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: laravel-upgrade
spec:
  template:
    spec:
      containers:
        - name: upgrade-agent
          image: ghcr.io/reyemtech/laravel-upgrade-agent:latest
          env:
            - name: REPO_URL
              value: "git@github.com:your-org/your-app.git"
            - name: TARGET_LARAVEL
              value: "12"
            - name: CLAUDE_CODE_OAUTH_TOKEN
              valueFrom:
                secretKeyRef:
                  name: upgrade-agent-secrets
                  key: claude-token
            - name: GIT_SSH_KEY_B64
              valueFrom:
                secretKeyRef:
                  name: upgrade-agent-secrets
                  key: deploy-key-b64
            - name: GH_TOKEN
              valueFrom:
                secretKeyRef:
                  name: upgrade-agent-secrets
                  key: gh-token
          volumeMounts:
            - name: output
              mountPath: /output
      volumes:
        - name: output
          emptyDir: {}
      restartPolicy: Never
  backoffLimit: 0
```

## How the Agent Stays on Track

- **Recon before action** — `recon.sh` maps the repo (package usage, component counts, test shape) so the agent can plan ahead
- **Three-file memory** — `plan.md`, `checklist.yaml`, and `run-log.md` survive context compaction and restarts
- **Ralph loop** — if Claude Code exits before the checklist is complete, it restarts with full context (up to `MAX_RESTARTS` times)
- **Loop breaker** — after 3 failed attempts on the same error, the agent logs the failure, marks the phase as `failed`, and moves on
- **Verification gates** — fast verification after every change, full verification before each phase commit
- **No CLAUDE.md overwrite** — upgrade instructions go to `.upgrade/CLAUDE.md`; your project's own `CLAUDE.md` is preserved

## Security

- Use a **repo-scoped deploy key**, not your personal SSH key
- API keys/tokens are passed as env vars, never baked into the image
- Container is ephemeral — destroyed after run
- Review the upgrade branch before merging

## License

[Business Source License 1.1](LICENSE) — You may use this software for any purpose except providing a commercial hosted service that runs it on behalf of third parties. Each release converts to Apache 2.0 four years after its release date.
