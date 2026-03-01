#!/bin/bash
# recon.sh — JS repo analysis: produces .upgrade/recon-report.md
# All commands are defensive (non-fatal) — recon must never fail the entrypoint.
set -e

cd /workspace
REPORT=".upgrade/recon-report.md"
mkdir -p .upgrade

# --- Header ---
echo "# Recon Report" > "$REPORT"
echo "" >> "$REPORT"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$REPORT"
echo "" >> "$REPORT"

# --- Stack Detection ---
echo "## Stack Detection" >> "$REPORT"
echo "" >> "$REPORT"
STACK_TYPE="${STACK_TYPE:-$(/skill/scripts/detect-stack.sh 2>/dev/null || echo "unknown")}"
echo "- **Detected stack:** \`$STACK_TYPE\`" >> "$REPORT"
echo "" >> "$REPORT"

# --- Package Manager ---
echo "## Package Manager" >> "$REPORT"
echo "" >> "$REPORT"
if [ -f pnpm-lock.yaml ]; then
  PKG_MANAGER="${PKG_MANAGER:-pnpm}"
  LOCKFILE="pnpm-lock.yaml"
elif [ -f yarn.lock ]; then
  PKG_MANAGER="${PKG_MANAGER:-yarn}"
  LOCKFILE="yarn.lock"
elif [ -f package-lock.json ]; then
  PKG_MANAGER="${PKG_MANAGER:-npm}"
  LOCKFILE="package-lock.json"
else
  PKG_MANAGER="${PKG_MANAGER:-npm}"
  LOCKFILE="(none found — npm default)"
fi
echo "- **Package manager:** \`$PKG_MANAGER\`" >> "$REPORT"
echo "- **Lockfile:** \`$LOCKFILE\`" >> "$REPORT"
if command -v "$PKG_MANAGER" > /dev/null 2>&1; then
  PM_VERSION=$("$PKG_MANAGER" --version 2>/dev/null || echo "unknown")
  echo "- **Version:** \`$PM_VERSION\`" >> "$REPORT"
fi
echo "" >> "$REPORT"

# --- Framework Versions ---
echo "## Framework Versions" >> "$REPORT"
echo "" >> "$REPORT"
if [ -f package.json ]; then
  for pkg in react react-dom next vite "@vitejs/plugin-react" react-scripts typescript; do
    VERSION=$(jq -r --arg p "$pkg" '(.dependencies[$p] // .devDependencies[$p] // null)' package.json 2>/dev/null)
    if [ "$VERSION" != "null" ] && [ -n "$VERSION" ]; then
      echo "- **$pkg:** \`$VERSION\`" >> "$REPORT"
    fi
  done
else
  echo "- No package.json found" >> "$REPORT"
fi
echo "" >> "$REPORT"

# --- Dependencies Overview ---
echo "## Dependencies Overview" >> "$REPORT"
echo "" >> "$REPORT"
if [ -f package.json ]; then
  DEP_COUNT=$(jq '(.dependencies // {}) | length' package.json 2>/dev/null || echo 0)
  DEV_COUNT=$(jq '(.devDependencies // {}) | length' package.json 2>/dev/null || echo 0)
  echo "- **Production deps:** $DEP_COUNT" >> "$REPORT"
  echo "- **Dev deps:** $DEV_COUNT" >> "$REPORT"
  echo "" >> "$REPORT"
  echo "### Production Dependencies" >> "$REPORT"
  echo "" >> "$REPORT"
  jq -r '.dependencies // {} | to_entries[] | "- \(.key): \(.value)"' package.json 2>/dev/null >> "$REPORT" || true
  echo "" >> "$REPORT"
  echo "### Dev Dependencies" >> "$REPORT"
  echo "" >> "$REPORT"
  jq -r '.devDependencies // {} | to_entries[] | "- \(.key): \(.value)"' package.json 2>/dev/null >> "$REPORT" || true
fi
echo "" >> "$REPORT"

# --- Test Runner ---
echo "## Test Runner" >> "$REPORT"
echo "" >> "$REPORT"
if [ -f package.json ]; then
  if jq -e '.devDependencies.vitest // .dependencies.vitest' package.json > /dev/null 2>&1; then
    echo "- **Runner:** vitest" >> "$REPORT"
  elif jq -e '.devDependencies.jest // .dependencies.jest' package.json > /dev/null 2>&1; then
    echo "- **Runner:** jest" >> "$REPORT"
  elif jq -e '.scripts.test' package.json > /dev/null 2>&1; then
    TEST_CMD=$(jq -r '.scripts.test' package.json 2>/dev/null)
    echo "- **Runner:** npm test (\`$TEST_CMD\`)" >> "$REPORT"
  else
    echo "- **Runner:** none detected" >> "$REPORT"
  fi
fi
TEST_FILE_COUNT=$(find . -name "*.test.*" -o -name "*.spec.*" 2>/dev/null | grep -v node_modules | wc -l | tr -d ' ')
echo "- **Test files:** $TEST_FILE_COUNT" >> "$REPORT"
echo "" >> "$REPORT"

# --- Build Tool ---
echo "## Build Tool" >> "$REPORT"
echo "" >> "$REPORT"
if [ -f package.json ]; then
  BUILD_SCRIPT=$(jq -r '.scripts.build // ""' package.json 2>/dev/null)
  if echo "$BUILD_SCRIPT" | grep -q "next build"; then
    echo "- **Build tool:** Next.js (\`next build\`)" >> "$REPORT"
  elif echo "$BUILD_SCRIPT" | grep -q "vite build"; then
    echo "- **Build tool:** Vite (\`vite build\`)" >> "$REPORT"
  elif echo "$BUILD_SCRIPT" | grep -q "react-scripts build"; then
    echo "- **Build tool:** Create React App (\`react-scripts build\`)" >> "$REPORT"
  elif [ -n "$BUILD_SCRIPT" ]; then
    echo "- **Build tool:** custom (\`$BUILD_SCRIPT\`)" >> "$REPORT"
  else
    echo "- **Build tool:** none detected" >> "$REPORT"
  fi
fi
echo "" >> "$REPORT"

# --- TypeScript ---
echo "## TypeScript" >> "$REPORT"
echo "" >> "$REPORT"
if [ -f tsconfig.json ]; then
  TS_VERSION=$(jq -r '.devDependencies.typescript // .dependencies.typescript // null' package.json 2>/dev/null)
  echo "- **TypeScript:** enabled" >> "$REPORT"
  if [ "$TS_VERSION" != "null" ] && [ -n "$TS_VERSION" ]; then
    echo "- **Version:** \`$TS_VERSION\`" >> "$REPORT"
  fi
  echo "- **Config:** tsconfig.json" >> "$REPORT"
  [ -f tsconfig.app.json ] && echo "- tsconfig.app.json present" >> "$REPORT"
  [ -f tsconfig.node.json ] && echo "- tsconfig.node.json present" >> "$REPORT"
else
  echo "- **TypeScript:** not configured (no tsconfig.json)" >> "$REPORT"
fi
echo "" >> "$REPORT"

# --- Lockfile Type ---
echo "## Lockfile" >> "$REPORT"
echo "" >> "$REPORT"
[ -f pnpm-lock.yaml ] && echo "- pnpm-lock.yaml" >> "$REPORT"
[ -f yarn.lock ] && echo "- yarn.lock" >> "$REPORT"
[ -f package-lock.json ] && echo "- package-lock.json" >> "$REPORT"
if [ ! -f pnpm-lock.yaml ] && [ ! -f yarn.lock ] && [ ! -f package-lock.json ]; then
  echo "- No lockfile found" >> "$REPORT"
fi
echo "" >> "$REPORT"

# --- Outdated Packages ---
echo "## Outdated Packages" >> "$REPORT"
echo "" >> "$REPORT"
echo "Running \`$PKG_MANAGER outdated\` (this may take a moment)..." >> "$REPORT"
echo "" >> "$REPORT"
# npm outdated exits 1 when packages are outdated — always use || true
case "$PKG_MANAGER" in
  pnpm)
    OUTDATED=$(pnpm outdated --json 2>/dev/null || true)
    if [ -n "$OUTDATED" ] && command -v jq > /dev/null 2>&1; then
      echo "$OUTDATED" | jq -r 'to_entries[] | "- \(.key): \(.value.current) → \(.value.latest)"' 2>/dev/null >> "$REPORT" || echo "$OUTDATED" >> "$REPORT"
    else
      pnpm outdated 2>/dev/null >> "$REPORT" || true
    fi
    ;;
  yarn)
    yarn outdated 2>/dev/null >> "$REPORT" || true
    ;;
  npm)
    OUTDATED=$(npm outdated --json 2>/dev/null || true)
    if [ -n "$OUTDATED" ] && command -v jq > /dev/null 2>&1; then
      echo "$OUTDATED" | jq -r 'to_entries[] | "- \(.key): \(.value.current) → \(.value.latest)"' 2>/dev/null >> "$REPORT" || echo "$OUTDATED" >> "$REPORT"
    else
      npm outdated 2>/dev/null >> "$REPORT" || true
    fi
    ;;
esac
echo "" >> "$REPORT"

# --- Environment Variables ---
echo "## Environment Variables" >> "$REPORT"
echo "" >> "$REPORT"
PROCESS_ENV_COUNT=$(grep -r "process\.env\." src/ app/ pages/ components/ lib/ utils/ 2>/dev/null | grep -v node_modules | wc -l | tr -d ' ')
META_ENV_COUNT=$(grep -r "import\.meta\.env\." src/ app/ pages/ components/ lib/ utils/ 2>/dev/null | grep -v node_modules | wc -l | tr -d ' ')
echo "- **process.env.* usages:** $PROCESS_ENV_COUNT" >> "$REPORT"
echo "- **import.meta.env.* usages:** $META_ENV_COUNT" >> "$REPORT"
echo "" >> "$REPORT"
echo "### Unique process.env variables" >> "$REPORT"
echo "" >> "$REPORT"
grep -rh "process\.env\.\([A-Z_][A-Z0-9_]*\)" src/ app/ pages/ components/ lib/ utils/ 2>/dev/null | \
  grep -o "process\.env\.[A-Z_][A-Z0-9_]*" | sort -u | sed 's/^/- /' >> "$REPORT" 2>/dev/null || \
  echo "- (none found or source dirs not present)" >> "$REPORT"
echo "" >> "$REPORT"
echo "### Unique import.meta.env variables" >> "$REPORT"
echo "" >> "$REPORT"
grep -rh "import\.meta\.env\.\([A-Z_][A-Z0-9_]*\)" src/ app/ pages/ components/ lib/ utils/ 2>/dev/null | \
  grep -o "import\.meta\.env\.[A-Z_][A-Z0-9_]*" | sort -u | sed 's/^/- /' >> "$REPORT" 2>/dev/null || \
  echo "- (none found or source dirs not present)" >> "$REPORT"
echo "" >> "$REPORT"

# --- Custom Plugins ---
echo "## Custom Plugins / Bundler Config" >> "$REPORT"
echo "" >> "$REPORT"
VITE_CONFIG=""
for f in vite.config.ts vite.config.js vite.config.mts vite.config.mjs; do
  [ -f "$f" ] && VITE_CONFIG="$f" && break
done
WEBPACK_CONFIG=""
for f in webpack.config.js webpack.config.ts; do
  [ -f "$f" ] && WEBPACK_CONFIG="$f" && break
done
if [ -n "$VITE_CONFIG" ]; then
  echo "- **Vite config:** \`$VITE_CONFIG\`" >> "$REPORT"
  echo "" >> "$REPORT"
  echo "  Plugins referenced:" >> "$REPORT"
  grep -E "^\s*(import|const|//)" "$VITE_CONFIG" 2>/dev/null | grep -i "plugin\|Plugin" | head -10 | sed 's/^/  /' >> "$REPORT" 2>/dev/null || true
fi
if [ -n "$WEBPACK_CONFIG" ]; then
  echo "- **Webpack config:** \`$WEBPACK_CONFIG\`" >> "$REPORT"
  echo "" >> "$REPORT"
  echo "  Plugins referenced:" >> "$REPORT"
  grep -i "new.*[Pp]lugin\|require.*plugin" "$WEBPACK_CONFIG" 2>/dev/null | head -10 | sed 's/^/  /' >> "$REPORT" 2>/dev/null || true
fi
if [ -z "$VITE_CONFIG" ] && [ -z "$WEBPACK_CONFIG" ]; then
  echo "- No vite.config.* or webpack.config.* found" >> "$REPORT"
fi
echo "" >> "$REPORT"

# ============================================================
# Stack-specific sections
# ============================================================

if [ "$STACK_TYPE" = "nextjs" ]; then
  echo "## Next.js Specific" >> "$REPORT"
  echo "" >> "$REPORT"

  # next.config format
  NEXT_CONFIG=""
  for f in next.config.mjs next.config.ts next.config.js; do
    [ -f "$f" ] && NEXT_CONFIG="$f" && break
  done
  [ -n "$NEXT_CONFIG" ] && echo "- **next.config:** \`$NEXT_CONFIG\`" >> "$REPORT" || echo "- **next.config:** not found" >> "$REPORT"

  # Router type (app/ vs pages/)
  if [ -d app ]; then
    echo "- **Router:** App Router (\`app/\` directory)" >> "$REPORT"
  elif [ -d pages ]; then
    echo "- **Router:** Pages Router (\`pages/\` directory)" >> "$REPORT"
  else
    echo "- **Router:** unknown (no app/ or pages/ directory)" >> "$REPORT"
  fi

  # Middleware
  if [ -f middleware.ts ] || [ -f middleware.js ]; then
    echo "- **Middleware:** present" >> "$REPORT"
  else
    echo "- **Middleware:** not present" >> "$REPORT"
  fi

  # Image optimization config
  if [ -n "$NEXT_CONFIG" ] && grep -q "images" "$NEXT_CONFIG" 2>/dev/null; then
    echo "- **Image optimization:** custom config present" >> "$REPORT"
  else
    echo "- **Image optimization:** default (no custom images config)" >> "$REPORT"
  fi
  echo "" >> "$REPORT"

elif [ "$STACK_TYPE" = "cra" ]; then
  echo "## CRA Specific" >> "$REPORT"
  echo "" >> "$REPORT"

  # setupProxy.js
  if [ -f src/setupProxy.js ]; then
    echo "- **Dev proxy:** \`src/setupProxy.js\` present" >> "$REPORT"
  else
    echo "- **Dev proxy:** no setupProxy.js" >> "$REPORT"
  fi

  # custom-react-scripts
  if jq -e '.devDependencies["custom-react-scripts"] // .dependencies["custom-react-scripts"]' package.json > /dev/null 2>&1; then
    echo "- **custom-react-scripts:** yes — non-standard CRA fork" >> "$REPORT"
  else
    echo "- **custom-react-scripts:** no" >> "$REPORT"
  fi

  # Ejected status: check for config/ directory with webpack configs
  if [ -d config ] && ls config/webpack.config.* 2>/dev/null | grep -q .; then
    echo "- **Ejected:** YES — webpack config found in \`config/\`" >> "$REPORT"
  else
    echo "- **Ejected:** no" >> "$REPORT"
  fi
  echo "" >> "$REPORT"

elif [ "$STACK_TYPE" = "vite-react" ]; then
  echo "## Vite+React Specific" >> "$REPORT"
  echo "" >> "$REPORT"

  # Vite config format
  if [ -n "$VITE_CONFIG" ]; then
    echo "- **Vite config format:** \`$VITE_CONFIG\`" >> "$REPORT"
  fi

  # Plugins
  echo "" >> "$REPORT"
  echo "### Vite Plugin List" >> "$REPORT"
  echo "" >> "$REPORT"
  if [ -n "$VITE_CONFIG" ]; then
    grep -E "import\s+\w+\s+from\s+'@vitejs/|import\s+\w+\s+from\s+'vite-plugin" "$VITE_CONFIG" 2>/dev/null | \
      sed 's/^/- /' >> "$REPORT" || echo "- (could not parse plugin imports)" >> "$REPORT"
  else
    echo "- (no vite config found)" >> "$REPORT"
  fi
  echo "" >> "$REPORT"

  # CSS preprocessor
  echo "### CSS Preprocessor" >> "$REPORT"
  echo "" >> "$REPORT"
  if jq -e '.devDependencies.sass // .dependencies.sass // .devDependencies["sass-embedded"] // .dependencies["sass-embedded"]' package.json > /dev/null 2>&1; then
    echo "- **CSS preprocessor:** Sass/SCSS" >> "$REPORT"
  elif jq -e '.devDependencies.less // .dependencies.less' package.json > /dev/null 2>&1; then
    echo "- **CSS preprocessor:** Less" >> "$REPORT"
  elif jq -e '.devDependencies.stylus // .dependencies.stylus' package.json > /dev/null 2>&1; then
    echo "- **CSS preprocessor:** Stylus" >> "$REPORT"
  else
    echo "- **CSS preprocessor:** none detected (plain CSS)" >> "$REPORT"
  fi
  echo "" >> "$REPORT"
fi

echo ""
echo "Recon complete. Report saved to $REPORT"
