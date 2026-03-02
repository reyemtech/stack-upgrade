#!/bin/bash
set -e

# Validate required env vars
: "${REPO_URL:?REPO_URL is required}"

# Auth: support both Anthropic API key and Claude Max OAuth token
if [ -z "$ANTHROPIC_API_KEY" ] && [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  echo "ERROR: Set either ANTHROPIC_API_KEY (API key) or CLAUDE_CODE_OAUTH_TOKEN (Claude Max via 'claude setup-token')"
  exit 1
fi

# Setup repo access: SSH key or HTTPS via GH_TOKEN
if [ -n "$GIT_SSH_KEY_B64" ]; then
  mkdir -p ~/.ssh
  echo "$GIT_SSH_KEY_B64" | base64 -d > ~/.ssh/id_ed25519
  chmod 600 ~/.ssh/id_ed25519
  ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null
elif [ -n "$GH_TOKEN" ]; then
  git config --global credential.helper '!f() { echo "password=$GH_TOKEN"; }; f'
  if echo "$REPO_URL" | grep -q '^git@'; then
    REPO_URL=$(echo "$REPO_URL" | sed 's|^git@github.com:|https://github.com/|; s|\.git$||').git
  fi
else
  echo "ERROR: Set either GIT_SSH_KEY_B64 (SSH) or GH_TOKEN (HTTPS) for repo access"
  exit 1
fi

# Configure git
git config --global user.name "Node Upgrade Agent"
git config --global user.email "agent@reyem.tech"

echo "Cloning $REPO_URL ..."
git clone "$REPO_URL" /workspace
cd /workspace

# Stack detection (auto-detect, with optional STACK_TYPE override)
AUTO_DETECTED=$(/skill/scripts/detect-stack.sh /workspace)
if [ -n "$STACK_TYPE" ]; then
  if [ "$STACK_TYPE" != "$AUTO_DETECTED" ]; then
    echo "WARNING: STACK_TYPE='$STACK_TYPE' but auto-detection found '$AUTO_DETECTED'. Using override."
  fi
else
  STACK_TYPE="$AUTO_DETECTED"
fi
export STACK_TYPE
echo "Stack type: $STACK_TYPE"

# Determine TARGET_VERSION for the branch name based on STACK_TYPE
if [ "$STACK_TYPE" = "nextjs" ] && [ -n "$TARGET_NEXTJS" ]; then
  TARGET_VERSION="$TARGET_NEXTJS"
elif [ "$STACK_TYPE" = "vite-react" ] && [ -n "$TARGET_VITE" ]; then
  TARGET_VERSION="$TARGET_VITE"
elif [ "$STACK_TYPE" = "cra" ] && [ -n "$TARGET_REACT" ]; then
  TARGET_VERSION="$TARGET_REACT"
else
  TARGET_VERSION="latest"
fi
export TARGET_VERSION

# Branch name: support optional suffix for repeat runs
BRANCH="upgrade/node-${STACK_TYPE}-${TARGET_VERSION}"
if [ -n "$BRANCH_SUFFIX" ]; then
  BRANCH="upgrade/node-${STACK_TYPE}-${TARGET_VERSION}-${BRANCH_SUFFIX}"
fi
export BRANCH

if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  echo "Remote branch $BRANCH exists — checking out and pulling latest..."
  git checkout -t "origin/$BRANCH"
  git pull --rebase origin "$BRANCH"
else
  echo "Creating new branch $BRANCH..."
  git checkout -b "$BRANCH"
fi

# Package manager detection
if [ -f pnpm-lock.yaml ]; then PKG_MANAGER="pnpm"
elif [ -f yarn.lock ]; then PKG_MANAGER="yarn"
else PKG_MANAGER="npm"; fi
export PKG_MANAGER
echo "Package manager: $PKG_MANAGER"

# Best-effort dependency install (non-fatal — Claude Code will fix deps)
echo "Installing current dependencies..."
case "$PKG_MANAGER" in
  pnpm)
    pnpm install --frozen-lockfile 2>/dev/null || pnpm install \
      || echo "WARNING: Dependency install failed. Claude Code will handle this."
    ;;
  yarn)
    yarn install --frozen-lockfile 2>/dev/null || yarn install \
      || echo "WARNING: Dependency install failed. Claude Code will handle this."
    ;;
  npm)
    npm ci 2>/dev/null || npm install \
      || echo "WARNING: Dependency install failed. Claude Code will handle this."
    ;;
esac

# Before-snapshots (for diff-based review — INFRA-09)
echo "Capturing pre-upgrade dependency snapshots..."
jq '{dependencies: (.dependencies // {}), devDependencies: (.devDependencies // {})}' package.json \
  > /output/before-package-deps.json 2>/dev/null \
  || echo "{}" > /output/before-package-deps.json
for lockfile in package-lock.json yarn.lock pnpm-lock.yaml; do
  if [ -f "$lockfile" ]; then
    sha256sum "$lockfile" > /output/before-lockfile-hash.txt
    break
  fi
done

# Best-effort baseline verification (non-fatal)
echo "Running baseline verification..."
/skill/scripts/verify-full.sh 2>&1 | tee /output/baseline.log \
  || echo "WARNING: Baseline verification had failures (expected pre-upgrade)."

# Create .upgrade/ directory for all upgrade artifacts (INFRA-07 two-tier template merge)
mkdir -p .upgrade/scripts
export UPGRADE_DATE=$(date -u +%Y-%m-%d)

# Tier 1: shared base templates
cp /skill/templates/shared/run-log.md .upgrade/run-log.md
cp /skill/templates/shared/changelog.md .upgrade/changelog.md

# Tier 2: stack-specific overlay
envsubst < /skill/templates/"$STACK_TYPE"/plan.md > .upgrade/plan.md
envsubst < /skill/templates/"$STACK_TYPE"/checklist.yaml > .upgrade/checklist.yaml
cp /skill/templates/"$STACK_TYPE"/CLAUDE.md .upgrade/CLAUDE.md

# Scripts
cp /skill/scripts/verify-fast.sh .upgrade/scripts/verify-fast.sh
cp /skill/scripts/verify-full.sh .upgrade/scripts/verify-full.sh
chmod +x .upgrade/scripts/verify-*.sh

# Fetch upgrade docs (non-fatal)
echo "Fetching upgrade guide..."
case "$STACK_TYPE" in
  nextjs)
    if [ -n "$TARGET_NEXTJS" ]; then
      curl -fsSL "https://nextjs.org/docs/app/guides/upgrading/version-${TARGET_NEXTJS}" \
        -o .upgrade/nextjs-upgrade-guide.html 2>/dev/null \
        && echo "Next.js ${TARGET_NEXTJS} upgrade guide saved" \
        || echo "WARNING: Could not fetch version-specific guide (non-fatal)."
    else
      curl -fsSL "https://nextjs.org/docs/app/building-your-application/upgrading" \
        -o .upgrade/nextjs-upgrade-guide.html 2>/dev/null \
        && echo "Next.js upgrade guide saved" \
        || echo "WARNING: Could not fetch upgrade guide (non-fatal)."
    fi
    ;;
  cra)
    curl -fsSL "https://vitejs.dev/guide/migration" \
      -o .upgrade/vite-migration-guide.html 2>/dev/null \
      && echo "Vite migration guide saved to .upgrade/vite-migration-guide.html" \
      || echo "WARNING: Could not fetch upgrade guide (non-fatal)."
    ;;
  vite-react)
    curl -fsSL "https://vitejs.dev/guide/migration" \
      -o .upgrade/vite-migration-guide.html 2>/dev/null \
      && echo "Vite migration guide saved to .upgrade/vite-migration-guide.html" \
      || echo "WARNING: Could not fetch upgrade guide (non-fatal)."
    ;;
esac

# Run recon to map the repo before the agent starts
echo "Running recon..."
/skill/scripts/recon.sh 2>&1 | tee /output/recon.log \
  || echo "WARNING: Recon had issues (non-fatal)."

# Launch Claude Code via Ralph loop
echo "Starting Claude Code via Ralph loop..."
exec /skill/scripts/ralph-loop.sh
