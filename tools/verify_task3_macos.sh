#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="BioMIRBackfill.xcodeproj"
SCHEME="BioMIRBackfill"
DERIVED="${TMPDIR:-/tmp}/BioMIRBackfill_Task3_DerivedData"
HARNESS="${TMPDIR:-/tmp}/BioMIRBackfill_Task3_Harness"

command -v xcodebuild >/dev/null 2>&1 || { echo "ERROR: xcodebuild not found." >&2; exit 1; }
command -v xcrun >/dev/null 2>&1 || { echo "ERROR: xcrun not found." >&2; exit 1; }
command -v swiftc >/dev/null 2>&1 || { echo "ERROR: swiftc not found." >&2; exit 1; }

echo "=== TASK 3 STRUCTURE / CONTROLLED MAPPING ==="
python3 tools/validate_task1.py
python3 tools/validate_task2.py
python3 tools/validate_task3.py
plutil -lint BioMIRBackfill/Supporting/Info.plist >/dev/null
plutil -lint BioMIRBackfill/Supporting/BioMIRBackfill.entitlements >/dev/null
plutil -lint BioMIRBackfill.xcodeproj/project.pbxproj >/dev/null
echo "Structure/plist validation: PASS"

echo
echo "=== TASK 3 PORTABLE BEHAVIOR ==="
rm -f "$HARNESS"
swiftc \
  BioMIRBackfill/Core/CSV/CSVModels.swift \
  BioMIRBackfill/Core/CSV/CSVParser.swift \
  BioMIRBackfill/Core/Mapping/MappingModels.swift \
  BioMIRBackfill/Core/Mapping/NutritionMappingRegistry.swift \
  BioMIRBackfill/Core/Mapping/MappingEngine.swift \
  tools/task3_portable_harness.swift \
  -o "$HARNESS"
"$HARNESS"

echo
echo "=== SELECT AVAILABLE IPHONE SIMULATOR ==="
UDID="$(python3 - <<'PY'
import json, subprocess, sys
payload = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
preferred = ["iPhone 17 Pro", "iPhone 17", "iPhone 16e"]
devices = [d for runtime in payload.get("devices", {}).values() for d in runtime if d.get("isAvailable") and d.get("name", "").startswith("iPhone")]
for name in preferred:
    for d in devices:
        if d.get("name") == name:
            print(d["udid"]); sys.exit(0)
if devices:
    print(devices[0]["udid"]); sys.exit(0)
sys.exit(1)
PY
)" || { echo "ERROR: No available iPhone simulator." >&2; exit 1; }

echo "Simulator UDID: $UDID"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

echo
echo "=== TASK 3 XCTEST ==="
rm -rf "$DERIVED"
xcodebuild -quiet \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  test

echo "XCTest: PASS"
echo
echo "TASK 3 MACOS VERIFICATION: PASS"
