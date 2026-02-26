#!/bin/bash
set -e

# Validate required env vars
: "${REPO_URL:?REPO_URL is required}"
: "${TARGET_LARAVEL:?TARGET_LARAVEL is required}"
: "${GIT_SSH_KEY_B64:?GIT_SSH_KEY_B64 is required}"

# Auth: support both Anthropic API key and Claude Max OAuth token
if [ -z "$ANTHROPIC_API_KEY" ] && [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  echo "ERROR: Set either ANTHROPIC_API_KEY (API key) or CLAUDE_CODE_OAUTH_TOKEN (Claude Max via 'claude setup-token')"
  exit 1
fi

# Setup SSH
mkdir -p ~/.ssh
echo "$GIT_SSH_KEY_B64" | base64 -d > ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null

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

# Create .upgrade/ directory for all upgrade artifacts
mkdir -p .upgrade/scripts

# Drop templates with variable substitution
export UPGRADE_DATE=$(date -u +%Y-%m-%d)
envsubst < /skill/templates/plan.md > .upgrade/plan.md
envsubst < /skill/templates/checklist.yaml > .upgrade/checklist.yaml
cp /skill/templates/run-log.md .upgrade/run-log.md
cp /skill/templates/changelog.md .upgrade/changelog.md
cp /skill/templates/CLAUDE.md .upgrade/CLAUDE.md
cp /skill/scripts/verify-fast.sh .upgrade/scripts/verify-fast.sh
cp /skill/scripts/verify-full.sh .upgrade/scripts/verify-full.sh
chmod +x .upgrade/scripts/verify-*.sh

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
echo "Starting Claude Code via Ralph loop..."
exec /skill/scripts/ralph-loop.sh
