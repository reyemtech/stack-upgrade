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

# Clone + branch
echo "Cloning $REPO_URL ..."
git clone "$REPO_URL" /workspace
cd /workspace
git checkout -b "upgrade/laravel-${TARGET_LARAVEL}"

# Best-effort dependency install (non-fatal — Claude Code will fix deps)
echo "Installing current dependencies..."
if ! composer install --no-interaction --no-progress 2>&1; then
  echo "composer install failed, trying composer update..."
  if ! composer update --no-interaction --no-progress 2>&1; then
    echo "WARNING: Dependency install failed. Claude Code will handle this."
  fi
fi
npm ci 2>/dev/null || npm install 2>/dev/null || echo "WARNING: npm install failed. Claude Code will handle this."

# Best-effort baseline (non-fatal)
echo "Running baseline verification..."
/skill/scripts/verify-full.sh 2>&1 | tee /output/baseline.log || echo "WARNING: Baseline verification had failures (expected pre-upgrade)."

# Drop templates with variable substitution
export UPGRADE_DATE=$(date -u +%Y-%m-%d)
envsubst < /skill/templates/plan.md > plan.md
envsubst < /skill/templates/checklist.yaml > checklist.yaml
cp /skill/templates/run-log.md run-log.md
cp /skill/templates/CLAUDE.md CLAUDE.md
mkdir -p scripts
cp /skill/scripts/verify-fast.sh scripts/verify-fast.sh
cp /skill/scripts/verify-full.sh scripts/verify-full.sh
chmod +x scripts/verify-*.sh

# Initial commit with upgrade scaffolding
git add plan.md checklist.yaml run-log.md CLAUDE.md scripts/verify-*.sh
git commit -m "upgrade: scaffold upgrade to Laravel ${TARGET_LARAVEL}"

echo "Starting Claude Code via Ralph loop..."
exec /skill/scripts/ralph-loop.sh
