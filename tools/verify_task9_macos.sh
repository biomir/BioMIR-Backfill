#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== TASK 9 DOCUMENT / PRIVACY GATES ==="
python3 tools/validate_task9.py

echo
echo "=== TASK 8 REGRESSION BASELINE ==="
./tools/verify_task8_macos.sh

echo
echo "TASK 9 PRE-DEVICE VERIFICATION: PASS"
echo "Physical-device Gates 9A/9B/9C remain PENDING and must be executed manually on the signed iPhone."
