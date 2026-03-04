#!/bin/bash
# Fast verification loop — run after every file change
set -e

echo "=== verify-fast ==="

echo "[1/5] composer validate..."
composer validate --no-check-all --no-check-publish 2>&1

echo "[2/5] php artisan route:list..."
php artisan route:list 2>&1 | tail -5
echo "(route:list OK)"

echo "[3/5] php artisan test (fast)..."
php artisan test --stop-on-failure 2>&1

# [4/5] Pint auto-fix (if installed)
if [ -f vendor/bin/pint ]; then
  echo "[4/5] pint (auto-fix)..."
  php vendor/bin/pint 2>&1
else
  echo "[4/5] pint — skipped (not installed)"
fi

# [5/5] PHPStan (if configured)
if [ -f phpstan.neon ] || [ -f phpstan.neon.dist ]; then
  if [ -f vendor/bin/phpstan ]; then
    echo "[5/5] phpstan analyse..."
    php -d memory_limit=512M vendor/bin/phpstan analyse --no-progress 2>&1
  else
    echo "[5/5] phpstan — skipped (not installed)"
  fi
else
  echo "[5/5] phpstan — skipped (no config)"
fi

echo "=== verify-fast PASSED ==="
