#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== TASK 7 STRUCTURE ==="
python3 tools/validate_task1.py
python3 tools/validate_task2.py
python3 tools/validate_task3.py
python3 tools/validate_task4.py
python3 tools/validate_task5.py
python3 tools/validate_task6.py
python3 tools/validate_task7.py

echo
echo "=== TASK 7 PORTABLE VERIFICATION ==="
swiftc \
  BioMIRBackfill/Core/CSV/CSVModels.swift \
  BioMIRBackfill/Core/CSV/CSVParser.swift \
  BioMIRBackfill/Core/Audit/SourceFingerprint.swift \
  BioMIRBackfill/Core/CSV/SourceDocumentService.swift \
  BioMIRBackfill/Core/Mapping/MappingModels.swift \
  BioMIRBackfill/Core/HealthKit/HealthAuthorizationState.swift \
  BioMIRBackfill/Core/HealthKit/HealthStoreGateway.swift \
  BioMIRBackfill/Core/Audit/ImportManifest.swift \
  BioMIRBackfill/Core/Import/ImportModels.swift \
  BioMIRBackfill/Core/Audit/ProvenanceService.swift \
  BioMIRBackfill/Core/Audit/AuditLedger.swift \
  BioMIRBackfill/Core/Verification/VerificationModels.swift \
  BioMIRBackfill/Core/Verification/VerificationEngine.swift \
  tools/task7_portable_harness.swift \
  -o /tmp/biomir_task7_harness
/tmp/biomir_task7_harness

echo
echo "=== TASK 7 AUDIT EXPORT TYPECHECK ==="
swiftc -typecheck \
  BioMIRBackfill/Core/CSV/CSVModels.swift \
  BioMIRBackfill/Core/CSV/CSVParser.swift \
  BioMIRBackfill/Core/Audit/SourceFingerprint.swift \
  BioMIRBackfill/Core/CSV/SourceDocumentService.swift \
  BioMIRBackfill/Core/Mapping/MappingModels.swift \
  BioMIRBackfill/Core/HealthKit/HealthAuthorizationState.swift \
  BioMIRBackfill/Core/HealthKit/HealthStoreGateway.swift \
  BioMIRBackfill/Core/Audit/ImportManifest.swift \
  BioMIRBackfill/Core/Import/ImportModels.swift \
  BioMIRBackfill/Core/Audit/AuditLedger.swift \
  BioMIRBackfill/Core/Verification/VerificationModels.swift \
  BioMIRBackfill/Core/Audit/AuditExporter.swift
echo "Task 7 audit export typecheck: PASS"

echo
echo "=== SELECT AVAILABLE IPHONE SIMULATOR ==="
UDID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone 17 Pro / {print $2; exit}')"
if [ -z "$UDID" ]; then
  UDID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ {print $2; exit}')"
fi
if [ -z "$UDID" ]; then
  echo "ERROR: No available iPhone simulator"
  exit 1
fi
echo "Simulator UDID: $UDID"

echo
echo "=== TASK 7 XCTEST ==="
rm -rf "${TMPDIR:-/tmp}/BioMIRBackfill_Task7_DerivedData"
xcodebuild \
  -project BioMIRBackfill.xcodeproj \
  -scheme BioMIRBackfill \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "${TMPDIR:-/tmp}/BioMIRBackfill_Task7_DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  test | tee /tmp/biomir_task7_xctest.log

grep -q "TEST SUCCEEDED" /tmp/biomir_task7_xctest.log

echo "XCTest: PASS"
echo
echo "TASK 7 MACOS VERIFICATION: PASS"
