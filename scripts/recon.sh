#!/bin/bash
# Recon: map the repo before the agent starts
# Produces .upgrade/recon-report.md

cd /workspace
REPORT=".upgrade/recon-report.md"

echo "# Recon Report" > "$REPORT"
echo "" >> "$REPORT"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$REPORT"
echo "" >> "$REPORT"

# Current versions
echo "## Current Versions" >> "$REPORT"
echo "" >> "$REPORT"
echo "- **PHP:** $(php -v 2>/dev/null | head -1 || echo 'unknown')" >> "$REPORT"
echo "- **Laravel:** $(php artisan --version 2>/dev/null || echo 'unknown')" >> "$REPORT"
echo "- **Node:** $(node -v 2>/dev/null || echo 'unknown')" >> "$REPORT"
echo "- **NPM:** $(npm -v 2>/dev/null || echo 'unknown')" >> "$REPORT"
echo "" >> "$REPORT"

# Composer package usage analysis
echo "## Composer Package Usage" >> "$REPORT"
echo "" >> "$REPORT"
echo "Packages in \`composer.json\` and whether they appear to be used in the codebase:" >> "$REPORT"
echo "" >> "$REPORT"
echo "| Package | Used | Evidence |" >> "$REPORT"
echo "|---------|------|----------|" >> "$REPORT"

if [ -f composer.json ]; then
  # Extract require packages (not require-dev)
  PACKAGES=$(jq -r '.require // {} | keys[] | select(. != "php" and (startswith("ext-") | not))' composer.json 2>/dev/null)
  for pkg in $PACKAGES; do
    # Convert package name to possible namespace fragments
    # e.g., laravel/framework -> Laravel, filament/filament -> Filament
    SEARCH_TERM=$(echo "$pkg" | awk -F/ '{print $NF}' | sed 's/-/\\\|/g')
    VENDOR=$(echo "$pkg" | awk -F/ '{print $1}')

    # Search for use statements, config references, or service provider references
    HITS=$(grep -rl "$SEARCH_TERM\|$VENDOR" app/ config/ routes/ resources/ 2>/dev/null | head -3)
    if [ -n "$HITS" ]; then
      EVIDENCE=$(echo "$HITS" | head -2 | tr '\n' ', ' | sed 's/,$//')
      echo "| $pkg | Yes | $EVIDENCE |" >> "$REPORT"
    else
      echo "| $pkg | **No** | Not found in app/, config/, routes/, resources/ |" >> "$REPORT"
    fi
  done
fi
echo "" >> "$REPORT"

# Filament / Livewire detection
echo "## Filament / Livewire" >> "$REPORT"
echo "" >> "$REPORT"

FILAMENT_INSTALLED=$(composer show filament/filament 2>/dev/null | head -1 || echo "")
if [ -n "$FILAMENT_INSTALLED" ]; then
  echo "- **Filament:** Installed ($FILAMENT_INSTALLED)" >> "$REPORT"
  FILAMENT_RESOURCES=$(find app -path "*/Filament/*" -name "*.php" 2>/dev/null | wc -l | tr -d ' ')
  echo "- **Filament resources/pages/widgets:** $FILAMENT_RESOURCES files" >> "$REPORT"
else
  echo "- **Filament:** Not installed" >> "$REPORT"
fi

LIVEWIRE_INSTALLED=$(composer show livewire/livewire 2>/dev/null | head -1 || echo "")
if [ -n "$LIVEWIRE_INSTALLED" ]; then
  echo "- **Livewire:** Installed ($LIVEWIRE_INSTALLED)" >> "$REPORT"
  LIVEWIRE_COMPONENTS=$(find app -path "*/Livewire/*" -name "*.php" 2>/dev/null | wc -l | tr -d ' ')
  echo "- **Livewire components:** $LIVEWIRE_COMPONENTS files" >> "$REPORT"
else
  echo "- **Livewire:** Not installed" >> "$REPORT"
fi

FLUX_INSTALLED=$(composer show livewire/flux 2>/dev/null | head -1 || echo "")
FLUX_PRO_INSTALLED=$(composer show livewire/flux-pro 2>/dev/null | head -1 || echo "")
[ -n "$FLUX_INSTALLED" ] && echo "- **Flux:** Installed ($FLUX_INSTALLED)" >> "$REPORT"
[ -n "$FLUX_PRO_INSTALLED" ] && echo "- **Flux Pro:** Installed ($FLUX_PRO_INSTALLED)" >> "$REPORT"
echo "" >> "$REPORT"

# Test suite shape
echo "## Test Suite" >> "$REPORT"
echo "" >> "$REPORT"

if [ -d tests ]; then
  UNIT_TESTS=$(find tests/Unit -name "*.php" 2>/dev/null | wc -l | tr -d ' ')
  FEATURE_TESTS=$(find tests/Feature -name "*.php" 2>/dev/null | wc -l | tr -d ' ')
  OTHER_TESTS=$(find tests -name "*.php" -not -path "tests/Unit/*" -not -path "tests/Feature/*" -not -name "TestCase.php" -not -name "CreatesApplication.php" -not -name "Pest.php" 2>/dev/null | wc -l | tr -d ' ')
  echo "- **Unit tests:** $UNIT_TESTS files" >> "$REPORT"
  echo "- **Feature tests:** $FEATURE_TESTS files" >> "$REPORT"
  echo "- **Other test files:** $OTHER_TESTS" >> "$REPORT"
  USES_PEST=$(grep -rl "uses()" tests/ 2>/dev/null | head -1)
  if [ -n "$USES_PEST" ]; then
    echo "- **Framework:** Pest" >> "$REPORT"
  else
    echo "- **Framework:** PHPUnit" >> "$REPORT"
  fi
else
  echo "- No tests/ directory found" >> "$REPORT"
fi
echo "" >> "$REPORT"

# NPM packages overview
echo "## NPM Packages" >> "$REPORT"
echo "" >> "$REPORT"

if [ -f package.json ]; then
  echo "### Dependencies" >> "$REPORT"
  jq -r '.dependencies // {} | to_entries[] | "- \(.key): \(.value)"' package.json 2>/dev/null >> "$REPORT"
  echo "" >> "$REPORT"
  echo "### Dev Dependencies" >> "$REPORT"
  jq -r '.devDependencies // {} | to_entries[] | "- \(.key): \(.value)"' package.json 2>/dev/null >> "$REPORT"
else
  echo "No package.json found." >> "$REPORT"
fi
echo "" >> "$REPORT"

# Key framework files
echo "## Key Files" >> "$REPORT"
echo "" >> "$REPORT"
[ -f config/app.php ] && echo "- config/app.php exists" >> "$REPORT"
[ -f bootstrap/app.php ] && echo "- bootstrap/app.php exists" >> "$REPORT"
[ -f routes/web.php ] && echo "- routes/web.php exists" >> "$REPORT"
[ -f routes/api.php ] && echo "- routes/api.php exists" >> "$REPORT"
[ -f vite.config.js ] && echo "- vite.config.js exists" >> "$REPORT"
[ -f vite.config.ts ] && echo "- vite.config.ts exists" >> "$REPORT"
[ -f tailwind.config.js ] && echo "- tailwind.config.js exists" >> "$REPORT"
[ -f postcss.config.js ] && echo "- postcss.config.js exists" >> "$REPORT"
[ -f phpunit.xml ] && echo "- phpunit.xml exists" >> "$REPORT"
[ -f phpunit.xml.dist ] && echo "- phpunit.xml.dist exists" >> "$REPORT"

echo ""
echo "Recon complete. Report saved to $REPORT"
