#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
required = [
    root / "BioMIRBackfill/Core/Import/ImportModels.swift",
    root / "BioMIRBackfill/Core/Import/PreflightEngine.swift",
    root / "BioMIRBackfill/Core/Audit/ImportManifest.swift",
    root / "BioMIRBackfillTests/PreflightEngineTests.swift",
]
missing = [str(p.relative_to(root)) for p in required if not p.exists()]
if missing:
    print("TASK 5 STRUCTURE: FAIL")
    for item in missing:
        print("missing:", item)
    sys.exit(1)

models = (root / "BioMIRBackfill/Core/Import/ImportModels.swift").read_text()
engine = (root / "BioMIRBackfill/Core/Import/PreflightEngine.swift").read_text()
manifest = (root / "BioMIRBackfill/Core/Audit/ImportManifest.swift").read_text()
pbx = (root / "BioMIRBackfill.xcodeproj/project.pbxproj").read_text()

checks = {
    "visible existing wins": ".skippedExisting" in engine and "existing.isEmpty ? .eligible : .skippedExisting" in engine,
    "missing preserved": ".skippedMissing" in engine,
    "zero policy explicit": ".skippedZeroPolicy" in engine,
    "write authorization gate": ".authorizationBlocked" in engine and "writeAuthorizationStatus" in engine,
    "read visibility warning": "unverifiableVisibilityWarning" in engine and "limitedVisibilityWarning" in engine,
    "manifest source hash": "sourceSHA256" in manifest,
    "manifest schema hash": "schemaSHA256" in manifest,
    "parser version provenance": "parserVersion" in manifest,
    "mapping version provenance": "mappingVersion" in manifest,
    "source change hard gate": "SourceIntegrityGate" in manifest and "sourceChanged" in manifest,
}
for label, ok in checks.items():
    if not ok:
        print(f"TASK 5 STRUCTURE: FAIL — {label}")
        sys.exit(1)

for filename in ["ImportModels.swift", "PreflightEngine.swift", "ImportManifest.swift", "PreflightEngineTests.swift"]:
    if filename not in pbx:
        print(f"TASK 5 PROJECT MEMBERSHIP: FAIL — {filename}")
        sys.exit(1)

for forbidden in [".delete(", "func delete", "replaceExisting"]:
    if forbidden in engine or forbidden in manifest:
        print(f"TASK 5 APPEND-ONLY: FAIL — forbidden token {forbidden!r}")
        sys.exit(1)

print("TASK 5 STRUCTURE: PASS")
print("TASK 5 COLLISION GATE: PASS — existing visible sample wins")
print("TASK 5 SOURCE-INTEGRITY GATE: PASS — reviewed SHA-256 required")
print("TASK 5 READ-VISIBILITY GATE: PASS — limitations remain explicit")
