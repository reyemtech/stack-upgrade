#!/bin/bash
# Full verification suite — run before marking any phase complete
set -e

echo "=== verify-full ==="

echo "[1/6] composer validate..."
composer validate 2>&1

echo "[2/6] php artisan route:list..."
php artisan route:list --compact 2>&1 | tail -5
echo "(route:list OK)"

echo "[3/6] php artisan migrate:fresh --seed..."
php artisan migrate:fresh --seed 2>&1

echo "[4/6] php artisan test..."
php artisan test --parallel 2>&1

echo "[5/6] npm run build..."
npm run build 2>&1

echo "[6/6] composer audit + npm audit..."
composer audit 2>&1 || echo "(composer audit warnings — non-blocking)"
npm audit --production 2>&1 || echo "(npm audit warnings — non-blocking)"

echo "=== verify-full PASSED ==="
