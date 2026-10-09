# Task 6 — Provenance and Resumable Append-Only Import Validation

**Date:** 2026-10-02
**Status:** IMPLEMENTED — macOS/Xcode XCTest gate pending

## Scope

Task 6 introduces the first write-capable orchestration layer. It does not change the production BioMIR app and does not add any HealthKit deletion, replacement, or rollback path.

Implemented components:

- `ProvenanceService`
- `AuditLedger`
- `ImportJournal`
- `ImportCoordinator`
- `AuditLedgerTests`
- `ImportCoordinatorTests`

## Controlled behavior

1. External identity is a deterministic UUIDv8/custom value derived from SHA-256 over source SHA-256, source row, Health quantity type, source calendar date, mapping version, and provenance-schema version.
2. Provenance metadata records batch UUID, source fingerprint, source schema fingerprint, parser/mapping versions, source date/field/unit, transformation ID/version, source row, source filename, and historical-import classification.
3. Audit records are append-only local JSONL events; summaries reconcile one latest disposition per subject within an import run.
4. Import-journal records are append-only local JSONL events; batch state is derived from start/success/failure events rather than updated in place.
5. Default batch size is 200; accepted configured batch size is 100...250. Final partial batch may contain fewer than 100 samples.
6. Source SHA-256 is rechecked immediately before import.
7. Write authorization is rechecked immediately before scheduling each eligible candidate.
8. App-authored deterministic external identities are queried before save as an additional repeat-import guard.
9. Every batch is journaled as started before `HealthStoreGateway.save` is called.
10. A failed batch is journaled as failed and import stops. No rollback or delete is attempted.
11. Resume is forward-only: execute a fresh preflight, then schedule only records that remain eligible/missing.

## TDD evidence

RED was established before production implementation: Task-6 tests and portable harness referenced `AuditLedger`, `ImportJournal`, `ProvenanceService`, and `ImportCoordinator` before those production types existed.

GREEN portable evidence in the implementation environment:

- audit ledger persists across reopen;
- journal persists and derives terminal batch state across reopen;
- deterministic UUID SHA-256 bytes cross-check against Python `hashlib.sha256`;
- first 100-sample batch succeeds and second planned 100-sample batch failure is journaled;
- fresh preflight identifies the first 100 as existing and imports only the remaining 150 as 100 + 50;
- source-hash mismatch stops before save;
- import-time authorization loss blocks save;
- deterministic app-authored external identity prevents repeat import even when the ordinary day-level collision query is simulated as invisible.

## Controlled ruling

The implementation plan mentions hashing exported audit artifacts in Task 6, while Task 7 owns `AuditExporter` and export-bundle creation. Task 6 therefore establishes the append-only audit/journal source records and provenance needed by the exporter. Hashing of the resulting exported audit artifact remains a Task-7 acceptance item; no export artifact exists in Task 6 to hash.

## Remaining platform gate

Run `./tools/verify_task6_macos.sh` on the controlled Xcode/macOS environment. Task 6 is not closed until it ends with:

```text
TASK 6 PORTABLE COORDINATION: PASS
XCTest: PASS
TASK 6 MACOS VERIFICATION: PASS
```

Physical-device HealthKit persistence remains deferred to the controlled personal-device validation stage. Simulator/XCTest validation does not authorize a bulk historical import.
