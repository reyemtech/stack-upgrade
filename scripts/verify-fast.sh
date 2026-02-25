#!/bin/bash
# Fast verification loop — run after every file change
set -e

echo "=== verify-fast ==="

echo "[1/3] composer validate..."
composer validate --no-check-all --no-check-publish 2>&1

echo "[2/3] php artisan route:list..."
php artisan route:list --compact 2>&1 | tail -5
echo "(route:list OK)"

echo "[3/3] php artisan test (fast)..."
php artisan test --parallel --stop-on-failure 2>&1

echo "=== verify-fast PASSED ==="
