# BioMIR Backfill — Task 2 Source Intake Validation

**Date:** 2026-10-02  
**Task:** Deterministic source intake, SHA-256 fingerprinting, CSV parsing, and calendar-day construction  
**Status:** IMPLEMENTED — macOS/Xcode XCTest gate pending

## Scope implemented

- Exact-byte source loading through `SourceDocumentService`.
- SHA-256 source fingerprinting through CryptoKit (`SourceFingerprint`).
- UTF-8 CSV parsing with optional UTF-8 BOM.
- Quoted-field parsing including escaped quote support.
- Required canonical `Date` column.
- Strict ISO `YYYY-MM-DD` source dates.
- Duplicate-header rejection.
- Duplicate-date rejection.
- Column-count mismatch rejection.
- Non-finite/non-numeric observation rejection.
- Explicit distinction among `.missing`, `.explicitZero`, and `.value(Double)`.
- Calendar-day interval creation using `Calendar` and source timezone.
- DST-safe day construction; no fixed 86,400-second assumption.

## TDD evidence

RED was established before production implementation: the Task-2 structure validator failed because the planned production files did not exist while the Task-2 tests already existed.

Expected RED missing files:

- `BioMIRBackfill/Core/CSV/CSVModels.swift`
- `BioMIRBackfill/Core/CSV/CSVParser.swift`
- `BioMIRBackfill/Core/CSV/SourceDocumentService.swift`
- `BioMIRBackfill/Core/Audit/SourceFingerprint.swift`

After implementation, structural validation passed.

## Portable behavior validation

A temporary Swift 6.2.1 harness compiled and executed the Foundation-only Task-2 core on Linux.

Verified behaviors:

- quoted-header parsing;
- explicit zero preservation;
- missing-cell preservation;
- numeric-value preservation;
- rejection of `NaN`;
- duplicate-date rejection;
- 23-hour America/New_York spring DST calendar day;
- 25-hour America/New_York fall DST calendar day.

Result:

`TASK 2 PORTABLE BEHAVIOR HARNESS: PASS`

Structural results:

- `TASK 1 STRUCTURE: PASS`
- `TASK 2 STRUCTURE: PASS`
- Swift frontend syntax parse: PASS
- Xcode project plist syntax: PASS

## Platform validation still required

The Linux execution environment does not provide Apple's CryptoKit or Xcode/iOS Simulator runtime. Therefore the following are not yet claimed as validated:

1. CryptoKit SHA-256 known-vector XCTest on Apple SDK.
2. `SourceDocumentService` XCTest on iOS Simulator.
3. Full Task-1 + Task-2 target compilation under the installed Xcode SDK.
4. Full XCTest suite on iOS Simulator.

Run on macOS:

```bash
cd "$HOME/Desktop/BioMIR_Backfill"
./tools/verify_task2_macos.sh
```

Task 2 is complete only if the script ends with:

`TASK 2 MACOS VERIFICATION: PASS`

## Regulatory/audit note

This task intentionally rejects malformed or ambiguous source records rather than silently repairing them. The original selected-file bytes are fingerprinted before parsing, and the data model preserves missing vs explicit zero as separate states. These controls support later provenance, traceability, and reproducible import-manifest generation.
