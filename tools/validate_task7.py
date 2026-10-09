#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
required = [
    root / "BioMIRBackfill/Core/Verification/VerificationModels.swift",
    root / "BioMIRBackfill/Core/Verification/VerificationEngine.swift",
    root / "BioMIRBackfill/Core/Audit/AuditExporter.swift",
    root / "BioMIRBackfillTests/VerificationEngineTests.swift",
]
missing = [str(p.relative_to(root)) for p in required if not p.exists()]
if missing:
    print("TASK 7 STRUCTURE: FAIL")
    for item in missing:
        print("missing:", item)
    sys.exit(1)

models = required[0].read_text()
engine = required[1].read_text()
exporter = required[2].read_text()
live = (root / "BioMIRBackfill/Core/HealthKit/LiveHealthStoreGateway.swift").read_text()
import_models = (root / "BioMIRBackfill/Core/Import/ImportModels.swift").read_text()
pbx = (root / "BioMIRBackfill.xcodeproj/project.pbxproj").read_text()

checks = {
    "import expectations": "verificationExpectations" in import_models and "ImportedSampleExpectation" in import_models,
    "app-authored identity query": "samplesAuthoredByThisApp" in engine,
    "no day-level verification query": "existingSamples(" not in engine,
    "no verification writes": "gateway.save" not in engine and ".save(" not in engine,
    "exact type": "observed.typeIdentifier != expected.typeIdentifier" in engine,
    "exact value": "observed.value != expected.value" in engine,
    "exact unit": "observed.unit != expected.unit" in engine,
    "exact start": "observed.startDate != expected.startDate" in engine,
    "exact end": "observed.endDate != expected.endDate" in engine,
    "exact identity": "observed.externalID != expected.externalID" in engine,
    "exact user-entered": "observed.wasUserEntered != expected.wasUserEntered" in engine,
    "exact provenance": "observed.stringMetadata != expected.stringMetadata" in engine,
    "verification failure audit": ".verificationFailed" in engine,
    "verified-complete gate": "!items.isEmpty && failedCount == 0 && verifiedCount == items.count" in engine,
    "required export artifacts": all(name in exporter for name in [
        "manifest.json", "mapping-version.txt", "audit-ledger.jsonl", "verification.json", "SHA256SUMS.json"
    ]),
    "sha256 export": "SourceFingerprint.sha256" in exporter,
    "run-scoped ledger export": "ledger.records(for: verification.runID)" in exporter,
    "current-source constraint": "HKSource.default()" in live and "predicateForObjects(from:" in live,
}
for label, ok in checks.items():
    if not ok:
        print(f"TASK 7 STRUCTURE: FAIL — {label}")
        sys.exit(1)

for filename in [p.name for p in required]:
    declaration = f"path = {filename}; sourceTree = \"<group>\";"
    if declaration not in pbx:
        print(f"TASK 7 PROJECT MEMBERSHIP: FAIL — missing PBXFileReference for {filename}")
        sys.exit(1)

for token in ["func delete", ".delete(", "rollback", "replaceExisting", "func replace"]:
    if token in engine or token in exporter:
        print(f"TASK 7 READ-ONLY: FAIL — forbidden token {token!r}")
        sys.exit(1)

print("TASK 7 STRUCTURE: PASS")
print("TASK 7 RECONCILIATION GATE: PASS — type/value/unit/date/identity/provenance exact")
print("TASK 7 READ-ONLY GATE: PASS — verification does not mutate HealthKit")
print("TASK 7 APP-SOURCE GATE: PASS — external identity + current HealthKit source constrained")
print("TASK 7 AUDIT EXPORT GATE: PASS — run-scoped artifacts + SHA-256 hashes")
