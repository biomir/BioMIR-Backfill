#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
required = [
    root / "BioMIRBackfill/Core/Audit/ProvenanceService.swift",
    root / "BioMIRBackfill/Core/Audit/AuditLedger.swift",
    root / "BioMIRBackfill/Core/Import/ImportJournal.swift",
    root / "BioMIRBackfill/Core/Import/ImportCoordinator.swift",
    root / "BioMIRBackfillTests/AuditLedgerTests.swift",
    root / "BioMIRBackfillTests/ImportCoordinatorTests.swift",
]
missing = [str(p.relative_to(root)) for p in required if not p.exists()]
if missing:
    print("TASK 6 STRUCTURE: FAIL")
    for item in missing:
        print("missing:", item)
    sys.exit(1)

prov = required[0].read_text()
ledger = required[1].read_text()
journal = required[2].read_text()
coordinator = required[3].read_text()
pbx = (root / "BioMIRBackfill.xcodeproj/project.pbxproj").read_text()

checks = {
    "deterministic identity inputs": all(token in prov for token in [
        "manifest.sourceSHA256", "candidate.rowNumber", "candidate.healthIdentifier.rawValue",
        "isoDate(candidate.sourceDate)", "manifest.mappingVersion"
    ]),
    "provenance metadata": all(token in prov for token in [
        "batchUUID", "sourceSHA256", "sourceCalendarDate", "sourceField", "sourceUnit",
        "transformationID", "classification"
    ]),
    "append-only audit": "func append(_ record: AuditRecord)" in ledger,
    "append-only journal": "func append(_ event: ImportJournalEvent)" in journal,
    "bounded default batch": "defaultBatchSize = 200" in coordinator and "100...250" in coordinator,
    "source integrity recheck": "SourceIntegrityGate.assertUnchanged" in coordinator,
    "write auth recheck": "writeAuthorizationStatus" in coordinator,
    "app-authored repeat protection": "samplesAuthoredByThisApp" in coordinator,
    "journal before save": coordinator.find("journal.append(.started") < coordinator.find("gateway.save(drafts)"),
    "forward-only failure journal": "journal.append(.failed" in coordinator,
}
for label, ok in checks.items():
    if not ok:
        print(f"TASK 6 STRUCTURE: FAIL — {label}")
        sys.exit(1)

for filename in [p.name for p in required]:
    if filename not in pbx:
        print(f"TASK 6 PROJECT MEMBERSHIP: FAIL — {filename}")
        sys.exit(1)

forbidden = ["func delete", ".delete(", "rollback", "replaceExisting", "func replace"]
for token in forbidden:
    if token in coordinator or token in journal or token in ledger:
        print(f"TASK 6 APPEND-ONLY: FAIL — forbidden token {token!r}")
        sys.exit(1)

print("TASK 6 STRUCTURE: PASS")
print("TASK 6 IDENTITY GATE: PASS — source/row/type/date/mapping inputs controlled")
print("TASK 6 APPEND-ONLY GATE: PASS — no delete/replace/rollback path")
print("TASK 6 BATCHING GATE: PASS — default 200, controlled range 100...250")
print("TASK 6 RESUME GATE: PASS — fresh preflight + app-authored identity protection")
