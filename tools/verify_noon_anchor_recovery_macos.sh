#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

HARNESS="${TMPDIR:-/tmp}/BioMIRBackfill_NoonAnchorRecovery_Harness"

echo "=== NOON ANCHOR RECOVERY STRUCTURE ==="
python3 tools/validate_noon_anchor_recovery.py

echo
echo "=== NOON ANCHOR RECOVERY PORTABLE BEHAVIOR ==="
rm -f "$HARNESS"

# ImportManifestFactory is compiled only when CryptoKit is importable. On macOS,
# that factory references the real source-loader/fingerprint/parser types, so the
# portable harness must include those production files as compiler inputs. Linux
# excludes the factory via #if canImport(CryptoKit), and SourceFingerprint.swift
# cannot be compiled there because CryptoKit is unavailable.
MANIFEST_SUPPORT_SOURCES=()
if [[ "$(uname -s)" == "Darwin" ]]; then
  MANIFEST_SUPPORT_SOURCES+=(
    BioMIRBackfill/Core/CSV/CSVParser.swift
    BioMIRBackfill/Core/CSV/SourceDocumentService.swift
    BioMIRBackfill/Core/Audit/SourceFingerprint.swift
  )
fi

swiftc -swift-version 6 -strict-concurrency=complete \
  BioMIRBackfill/Core/CSV/CSVModels.swift \
  "${MANIFEST_SUPPORT_SOURCES[@]}" \
  BioMIRBackfill/Core/Mapping/MappingModels.swift \
  BioMIRBackfill/Core/HealthKit/HealthAuthorizationState.swift \
  BioMIRBackfill/Core/HealthKit/HealthStoreGateway.swift \
  BioMIRBackfill/Core/Audit/ImportManifest.swift \
  BioMIRBackfill/Core/Import/ImportModels.swift \
  BioMIRBackfill/Core/Import/PreflightEngine.swift \
  BioMIRBackfill/Core/Audit/ProvenanceService.swift \
  BioMIRBackfill/Core/Audit/AuditLedger.swift \
  BioMIRBackfill/Core/Import/ImportJournal.swift \
  BioMIRBackfill/Core/Import/ImportCoordinator.swift \
  tools/noon_anchor_recovery_harness.swift \
  -o "$HARNESS"
"$HARNESS"

echo
echo "=== FULL CARB + TASK 1–8 REGRESSION / XCTEST ==="
./tools/verify_carbmanager_total_carb_macos.sh

echo
echo "NOON ANCHOR RECOVERY MACOS VERIFICATION: PASS"
echo "Physical-device legacy deletion and corrected re-import remain pending."
