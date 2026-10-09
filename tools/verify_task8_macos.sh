#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== TASK 8 STRUCTURE ==="
python3 tools/validate_task1.py
python3 tools/validate_task2.py
python3 tools/validate_task3.py
python3 tools/validate_task4.py
python3 tools/validate_task5.py
python3 tools/validate_task6.py
python3 tools/validate_task7.py
python3 tools/validate_task8.py

echo
echo "=== TASK 8 VIEW-MODEL PORTABLE WORKFLOW ==="
swiftc -swift-version 6 -strict-concurrency=complete \
  BioMIRBackfill/Core/CSV/CSVModels.swift \
  BioMIRBackfill/Core/CSV/CSVParser.swift \
  BioMIRBackfill/Core/Audit/SourceFingerprint.swift \
  BioMIRBackfill/Core/CSV/SourceDocumentService.swift \
  BioMIRBackfill/Core/Mapping/MappingModels.swift \
  BioMIRBackfill/Core/Mapping/NutritionMappingRegistry.swift \
  BioMIRBackfill/Core/Mapping/MappingEngine.swift \
  BioMIRBackfill/Core/HealthKit/HealthAuthorizationState.swift \
  BioMIRBackfill/Core/HealthKit/HealthStoreGateway.swift \
  BioMIRBackfill/Core/HealthKit/LiveHealthStoreGateway.swift \
  BioMIRBackfill/Core/Audit/ImportManifest.swift \
  BioMIRBackfill/Core/Import/ImportModels.swift \
  BioMIRBackfill/Core/Import/PreflightEngine.swift \
  BioMIRBackfill/Core/Audit/ProvenanceService.swift \
  BioMIRBackfill/Core/Audit/AuditLedger.swift \
  BioMIRBackfill/Core/Import/ImportJournal.swift \
  BioMIRBackfill/Core/Import/ImportCoordinator.swift \
  BioMIRBackfill/Core/Verification/VerificationModels.swift \
  BioMIRBackfill/Core/Verification/VerificationEngine.swift \
  BioMIRBackfill/Core/Audit/AuditExporter.swift \
  BioMIRBackfill/App/ImportViewModel.swift \
  tools/task8_portable_harness.swift \
  -o /tmp/biomir_task8_harness
/tmp/biomir_task8_harness
echo "TASK 8 STRICT CONCURRENCY COMPILE: PASS"

echo
echo "=== TASK 8 SWIFTUI PARSE ==="
swiftc -parse \
  BioMIRBackfill/App/ImportFlowView.swift \
  BioMIRBackfill/App/BioMIRBackfillApp.swift
echo "Task 8 SwiftUI parse: PASS"

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
echo "=== TASK 8 XCTEST ==="
rm -rf "${TMPDIR:-/tmp}/BioMIRBackfill_Task8_DerivedData"
xcodebuild \
  -project BioMIRBackfill.xcodeproj \
  -scheme BioMIRBackfill \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "${TMPDIR:-/tmp}/BioMIRBackfill_Task8_DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  test | tee /tmp/biomir_task8_xctest.log

grep -q "TEST SUCCEEDED" /tmp/biomir_task8_xctest.log

echo "XCTest: PASS"
echo
echo "TASK 8 MACOS VERIFICATION: PASS"
