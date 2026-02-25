#!/bin/bash
set -e

# Validate required env vars
: "${REPO_URL:?REPO_URL is required}"
: "${TARGET_LARAVEL:?TARGET_LARAVEL is required}"
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is required}"
: "${GIT_SSH_KEY_B64:?GIT_SSH_KEY_B64 is required}"

# Setup SSH
mkdir -p /root/.ssh
echo "$GIT_SSH_KEY_B64" | base64 -d > /root/.ssh/id_ed25519
chmod 600 /root/.ssh/id_ed25519
ssh-keyscan github.com >> /root/.ssh/known_hosts 2>/dev/null

# Configure git
git config --global user.name "Laravel Upgrade Agent"
git config --global user.email "agent@reyem.tech"

# Clone + branch
echo "Cloning $REPO_URL ..."
git clone "$REPO_URL" /workspace
cd /workspace
git checkout -b "upgrade/laravel-${TARGET_LARAVEL}"

# Install current deps + baseline
echo "Installing current dependencies..."
composer install --no-interaction --no-progress --quiet || composer update --no-interaction --no-progress --quiet
npm ci --silent 2>/dev/null || true

echo "Running baseline verification..."
/skill/scripts/verify-full.sh 2>&1 | tee /output/baseline.log || true

# Drop templates with variable substitution
export UPGRADE_DATE=$(date -u +%Y-%m-%d)
envsubst < /skill/templates/plan.md > plan.md
envsubst < /skill/templates/checklist.yaml > checklist.yaml
cp /skill/templates/run-log.md run-log.md
cp /skill/templates/CLAUDE.md CLAUDE.md
cp /skill/scripts/verify-fast.sh scripts/verify-fast.sh 2>/dev/null || { mkdir -p scripts && cp /skill/scripts/verify-fast.sh scripts/; }
cp /skill/scripts/verify-full.sh scripts/verify-full.sh 2>/dev/null || { mkdir -p scripts && cp /skill/scripts/verify-full.sh scripts/; }
chmod +x scripts/verify-*.sh

# Initial commit with upgrade scaffolding
git add plan.md checklist.yaml run-log.md CLAUDE.md scripts/verify-*.sh
git commit -m "upgrade: scaffold upgrade to Laravel ${TARGET_LARAVEL}"

echo "Starting Claude Code via Ralph loop..."
exec /skill/scripts/ralph-loop.sh
