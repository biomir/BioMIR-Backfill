#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

HARNESS="${TMPDIR:-/tmp}/BioMIRBackfill_CarbManagerTotalCarb_Harness"

echo "=== CARB MANAGER TOTAL-CARB STRUCTURE ==="
python3 tools/validate_carbmanager_total_carb.py

echo
echo "=== CARB MANAGER RECONSTRUCTION BUILDER TEST ==="
python3 tools/test_carbmanager_total_carbs_builder.py

echo
echo "=== CSV CRLF REGRESSION + CARB MANAGER PROFILE PORTABLE BEHAVIOR ==="
rm -f "$HARNESS"
swiftc \
  BioMIRBackfill/Core/CSV/CSVModels.swift \
  BioMIRBackfill/Core/CSV/CSVParser.swift \
  BioMIRBackfill/Core/Mapping/MappingModels.swift \
  BioMIRBackfill/Core/Mapping/NutritionMappingRegistry.swift \
  BioMIRBackfill/Core/Mapping/MappingEngine.swift \
  tools/carbmanager_total_carb_harness.swift \
  -o "$HARNESS"
"$HARNESS"

echo
echo "=== TASK 8 REGRESSION BASELINE ==="
./tools/verify_task8_macos.sh

echo
echo "CARB MANAGER TOTAL-CARB MACOS VERIFICATION: PASS"
echo "Physical-device carbohydrate preflight/import remains pending."
