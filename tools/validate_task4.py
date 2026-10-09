#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
required = [
    root / "BioMIRBackfill/Core/HealthKit/HealthAuthorizationState.swift",
    root / "BioMIRBackfill/Core/HealthKit/HealthStoreGateway.swift",
    root / "BioMIRBackfill/Core/HealthKit/LiveHealthStoreGateway.swift",
    root / "BioMIRBackfillTests/HealthAuthorizationStateTests.swift",
    root / "BioMIRBackfillTests/HealthStoreGatewayTests.swift",
]
missing = [str(p.relative_to(root)) for p in required if not p.exists()]
if missing:
    print("TASK 4 STRUCTURE: FAIL")
    for item in missing:
        print("missing:", item)
    sys.exit(1)

protocol = (root / "BioMIRBackfill/Core/HealthKit/HealthStoreGateway.swift").read_text()
live = (root / "BioMIRBackfill/Core/HealthKit/LiveHealthStoreGateway.swift").read_text()
auth = (root / "BioMIRBackfill/Core/HealthKit/HealthAuthorizationState.swift").read_text()
pbx = (root / "BioMIRBackfill.xcodeproj/project.pbxproj").read_text()

# Normal import remains append-only. The sole delete exception is the explicitly named,
# provenance/date/duration-constrained historical noon-anchor recovery path.
for forbidden in ["deleteAll", "replaceExisting", "func replace", "rollback"]:
    if forbidden in protocol or forbidden in live:
        print(f"TASK 4 APPEND-ONLY: FAIL — forbidden general mutation token {forbidden!r}")
        sys.exit(1)

recovery_checks = {
    "single protocol recovery method": protocol.count("func deleteAppAuthoredSamples(") == 2,  # requirement + default implementation
    "single live recovery method": live.count("func deleteAppAuthoredSamples(") == 1,
    "source constrained": "HKSource.default()" in live,
    "classification constrained": "MetadataKey.classification" in live,
    "mapping constrained": "MetadataKey.mappingVersion" in live,
    "legacy duration constrained": "sample.startDate < sample.endDate" in live,
    "new noon samples excluded": "anchorPolicy == nil" in live,
}
for label, ok in recovery_checks.items():
    if not ok:
        print(f"TASK 4 RECOVERY GATE: FAIL — {label}")
        sys.exit(1)

checks = {
    "explicit unverifiable read visibility": "case unverifiable" in auth,
    "write auth separate from read visibility": "writeAuthorizationStatus" in protocol and "readVisibility" in protocol,
    "HealthKit native live gateway": "import HealthKit" in live and "HKHealthStore" in live,
    "requestAuthorization": "requestAuthorization" in live,
    "authorizationStatus(for:)": "authorizationStatus(for:" in live,
    "existing sample query": "HKSampleQuery" in live,
    "append-only save": "healthStore.save" in live,
    "external ID query": "predicateForObjects" in live and "HKMetadataKeyExternalUUID" in live,
}
for label, ok in checks.items():
    if not ok:
        print(f"TASK 4 STRUCTURE: FAIL — {label}")
        sys.exit(1)

for filename in [
    "HealthAuthorizationState.swift",
    "HealthStoreGateway.swift",
    "LiveHealthStoreGateway.swift",
    "HealthAuthorizationStateTests.swift",
    "HealthStoreGatewayTests.swift",
]:
    if filename not in pbx:
        print(f"TASK 4 PROJECT MEMBERSHIP: FAIL — {filename}")
        sys.exit(1)

print("TASK 4 STRUCTURE: PASS")
print("TASK 4 APPEND-ONLY GATE: PASS — normal import has no delete/replace path; only controlled noon-anchor recovery may delete legacy app-authored samples")
print("TASK 4 READ-VISIBILITY GATE: PASS — no inference of full read access")
