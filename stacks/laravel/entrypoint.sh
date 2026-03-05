#!/bin/bash
set -e

# Validate required env vars
: "${REPO_URL:?REPO_URL is required}"
: "${TARGET_LARAVEL:?TARGET_LARAVEL is required}"

# Agent CLI selection (baked into image via ENV, can be overridden)
AGENT_CLI="${AGENT_CLI:-claude}"

# Auth: validate credentials for the selected agent
if [ "$AGENT_CLI" = "claude" ]; then
  if [ -z "$ANTHROPIC_API_KEY" ] && [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
    echo "ERROR: Set ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN"
    exit 1
  fi
elif [ "$AGENT_CLI" = "codex" ]; then
  if [ -z "$OPENAI_API_KEY" ] && [ -z "$CODEX_AUTH_JSON_B64" ]; then
    echo "ERROR: Set OPENAI_API_KEY or CODEX_AUTH_JSON_B64"
    exit 1
  fi
  # Setup Codex auth
  if [ -n "$OPENAI_API_KEY" ]; then
    printenv OPENAI_API_KEY | codex login --with-api-key
  elif [ -n "$CODEX_AUTH_JSON_B64" ]; then
    mkdir -p ~/.codex
    echo "$CODEX_AUTH_JSON_B64" | base64 -d > ~/.codex/auth.json
  fi
else
  echo "ERROR: Unknown AGENT_CLI: $AGENT_CLI (expected 'claude' or 'codex')"
  exit 1
fi

# Setup repo access: SSH key or HTTPS via GH_TOKEN
if [ -n "$GIT_SSH_KEY_B64" ]; then
  mkdir -p ~/.ssh
  echo "$GIT_SSH_KEY_B64" | base64 -d > ~/.ssh/id_ed25519
  chmod 600 ~/.ssh/id_ed25519
  ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null
elif [ -n "$GH_TOKEN" ]; then
  git config --global credential.helper '!f() { echo "username=x-access-token"; echo "password=$GH_TOKEN"; }; f'
  if echo "$REPO_URL" | grep -q '^git@'; then
    REPO_URL=$(echo "$REPO_URL" | sed 's|^git@github.com:|https://github.com/|; s|\.git$||').git
  fi
else
  echo "ERROR: Set either GIT_SSH_KEY_B64 (SSH) or GH_TOKEN (HTTPS) for repo access"
  exit 1
fi

# Configure git
git config --global user.name "Laravel Upgrade Agent"
git config --global user.email "agent@reyem.tech"

# Branch name: support optional suffix for repeat runs
BRANCH="upgrade/laravel-${TARGET_LARAVEL}"
if [ -n "$BRANCH_SUFFIX" ]; then
  BRANCH="upgrade/laravel-${TARGET_LARAVEL}-${BRANCH_SUFFIX}"
fi
export BRANCH

echo "Cloning $REPO_URL ..."
git clone "$REPO_URL" /workspace
cd /workspace

if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  echo "Remote branch $BRANCH exists — checking out and pulling latest..."
  git checkout -t "origin/$BRANCH"
  git pull --rebase origin "$BRANCH"
else
  echo "Creating new branch $BRANCH..."
  git checkout -b "$BRANCH"
fi

# Best-effort dependency install (non-fatal — Claude Code will fix deps)
echo "Installing current dependencies..."
if ! composer install --no-interaction --no-progress --prefer-dist 2>&1; then
  echo "composer install failed, trying composer update..."
  if ! composer update --no-interaction --no-progress --prefer-dist 2>&1; then
    echo "WARNING: Dependency install failed. Claude Code will handle this."
  fi
fi
npm ci 2>/dev/null || npm install 2>/dev/null || echo "WARNING: npm install failed. Claude Code will handle this."

# Setup Laravel environment
if [ -f .env.example ] && [ ! -f .env ]; then
  cp .env.example .env
fi
php artisan key:generate --force 2>/dev/null || true

# Before-snapshots (for diff-based review)
echo "Capturing pre-upgrade dependency snapshots..."
composer show --format=json > /output/before-composer.json 2>/dev/null || echo "{}" > /output/before-composer.json
npm ls --json > /output/before-npm.json 2>/dev/null || echo "{}" > /output/before-npm.json
php artisan --version > /output/before-versions.txt 2>/dev/null || echo "unknown" > /output/before-versions.txt

# Best-effort baseline (non-fatal)
echo "Running baseline verification..."
/skill/scripts/verify-full.sh 2>&1 | tee /output/baseline.log || echo "WARNING: Baseline verification had failures (expected pre-upgrade)."

# Capture quality tool baselines (non-fatal)
echo "Capturing quality tool baselines..."
mkdir -p /output/baseline

# Pint
if [ -f pint.json ] || composer show laravel/pint >/dev/null 2>&1; then
  if [ -f vendor/bin/pint ]; then
    ./vendor/bin/pint --test > /output/baseline/pint.log 2>&1 && echo "pass" > /output/baseline/pint.status || echo "fail" > /output/baseline/pint.status
  fi
fi

# PHPStan
if [ -f phpstan.neon ] || [ -f phpstan.neon.dist ]; then
  if [ -f vendor/bin/phpstan ]; then
    php -d memory_limit=512M ./vendor/bin/phpstan analyse --no-progress --error-format=json > /output/baseline/phpstan.json 2>&1 && echo "pass" > /output/baseline/phpstan.status || echo "fail" > /output/baseline/phpstan.status
  fi
fi

# ESLint
if npx eslint --version >/dev/null 2>&1; then
  npx eslint . > /output/baseline/eslint.log 2>&1 && echo "pass" > /output/baseline/eslint.status || echo "fail" > /output/baseline/eslint.status
fi

# Cypress (dry-run only — verify config parses)
if [ -f cypress.config.ts ] || [ -f cypress.config.js ]; then
  echo "detected" > /output/baseline/cypress.status
fi

# Playwright (detect only)
if [ -f playwright.config.ts ] || [ -f playwright.config.js ]; then
  echo "detected" > /output/baseline/playwright.status
fi

echo "Quality baselines captured to /output/baseline/"

# Create .upgrade/ directory for all upgrade artifacts
mkdir -p .upgrade/scripts

# Drop templates with variable substitution
export UPGRADE_DATE=$(date -u +%Y-%m-%d)
envsubst < /skill/templates/plan.md > .upgrade/plan.md
envsubst < /skill/templates/checklist.yaml > .upgrade/checklist.yaml
cp /skill/templates/run-log.md .upgrade/run-log.md
cp /skill/templates/changelog.md .upgrade/changelog.md
cp /skill/templates/AGENT.md .upgrade/AGENT.md
cp /skill/scripts/verify-fast.sh .upgrade/scripts/verify-fast.sh
cp /skill/scripts/verify-full.sh .upgrade/scripts/verify-full.sh
chmod +x .upgrade/scripts/verify-*.sh

# Copy quality baselines into .upgrade/ so the agent can read them
cp -r /output/baseline .upgrade/baseline 2>/dev/null || true

# Fetch the official Laravel upgrade guide
echo "Fetching Laravel upgrade guide..."
PREV_LARAVEL=$((TARGET_LARAVEL - 1))
curl -fsSL "https://laravel.com/docs/${TARGET_LARAVEL}.x/upgrade" \
  -o .upgrade/laravel-upgrade-guide.html 2>/dev/null \
  && echo "Upgrade guide saved to .upgrade/laravel-upgrade-guide.html" \
  || echo "WARNING: Could not fetch upgrade guide (non-fatal)."

# Run recon to map the repo before the agent starts
echo "Running recon..."
/skill/scripts/recon.sh 2>&1 | tee /output/recon.log || echo "WARNING: Recon had issues (non-fatal)."

# Ensure .env and database.sqlite are gitignored
grep -qxF '.env' .gitignore 2>/dev/null || echo '.env' >> .gitignore
grep -qxF 'database/database.sqlite' .gitignore 2>/dev/null || echo 'database/database.sqlite' >> .gitignore

# No scaffold commit — agent commits once per phase
echo "Starting $AGENT_CLI via Ralph loop..."
exec /skill/scripts/ralph-loop.sh
