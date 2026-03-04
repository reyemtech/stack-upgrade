#!/bin/bash
# Full verification suite — run before marking any phase complete
set -e

echo "=== verify-full ==="

echo "[1/9] composer validate..."
composer validate 2>&1

echo "[2/9] php artisan route:list..."
php artisan route:list 2>&1 | tail -5
echo "(route:list OK)"

echo "[3/9] php artisan migrate:fresh --seed..."
touch database/database.sqlite 2>/dev/null || true
php artisan migrate:fresh --seed --force 2>&1

echo "[4/9] php artisan test..."
php artisan test 2>&1

echo "[5/9] npm run build..."
npm run build 2>&1

echo "[6/9] composer audit + npm audit..."
composer audit 2>&1 || echo "(composer audit warnings — non-blocking)"
npm audit --production 2>&1 || echo "(npm audit warnings — non-blocking)"

# [7/9] Pint auto-fix (if installed)
if [ -f vendor/bin/pint ]; then
  echo "[7/9] pint (auto-fix)..."
  php vendor/bin/pint 2>&1
else
  echo "[7/9] pint — skipped (not installed)"
fi

# [8/9] PHPStan (if configured)
if [ -f phpstan.neon ] || [ -f phpstan.neon.dist ]; then
  if [ -f vendor/bin/phpstan ]; then
    echo "[8/9] phpstan analyse..."
    php -d memory_limit=512M vendor/bin/phpstan analyse --no-progress 2>&1
  else
    echo "[8/9] phpstan — skipped (not installed)"
  fi
else
  echo "[8/9] phpstan — skipped (no config)"
fi

# [9/9] ESLint (if installed)
if npx eslint --version >/dev/null 2>&1; then
  echo "[9/9] eslint..."
  npx eslint . 2>&1
else
  echo "[9/9] eslint — skipped (not installed)"
fi

echo "=== verify-full PASSED ==="
