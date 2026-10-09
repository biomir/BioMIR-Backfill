#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="BioMIRBackfill.xcodeproj"
SCHEME="BioMIRBackfill"
DERIVED="${TMPDIR:-/tmp}/BioMIRBackfill_Task1_DerivedData"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "ERROR: xcodebuild not found. Install/open Xcode first." >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "ERROR: xcrun not found." >&2
  exit 1
fi

echo "=== XCODE ==="
xcodebuild -version

echo
echo "=== PROJECT STRUCTURE ==="
python3 tools/validate_task1.py
plutil -lint BioMIRBackfill/Supporting/Info.plist
plutil -lint BioMIRBackfill/Supporting/BioMIRBackfill.entitlements
plutil -lint BioMIRBackfill.xcodeproj/project.pbxproj

echo
echo "=== SIMULATOR BUILD ==="
rm -rf "$DERIVED"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo
echo "=== SELECT AVAILABLE IPHONE SIMULATOR ==="
UDID="$(python3 - <<'PY'
import json, subprocess, sys
payload = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
for runtime, devices in payload.get("devices", {}).items():
    for device in devices:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            print(device["udid"])
            sys.exit(0)
sys.exit(1)
PY
)" || {
  echo "ERROR: No available iPhone simulator was found. Install an iOS simulator runtime in Xcode Settings > Platforms." >&2
  exit 1
}

echo "Simulator UDID: $UDID"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b

echo
echo "=== XCTEST ==="
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  test

echo
echo "TASK 1 MACOS VERIFICATION: PASS"
