# BioMIR Backfill — Task 7 Verification and Audit Export Validation

Date: 2026-10-02
Status: IMPLEMENTED — macOS/Xcode XCTest gate pending

## Scope

Task 7 adds deterministic post-write reconciliation and a local hashed audit bundle. It does not add any HealthKit mutation path.

## Controlled verification contract

For each sample reported as imported by Task 6, verification queries only the deterministic external identities for the current BioMIR Backfill HealthKit source. A sample is VERIFIED only when exactly one returned sample matches all controlled fields:

- HealthKit quantity type
- normalized numeric value
- controlled unit
- start date
- end date
- deterministic external UUID
- `HKMetadataKeyWasUserEntered`
- complete BioMIR Backfill string provenance metadata

Missing, duplicate, or mismatched samples are `VERIFICATION_FAILED`. `Verified Complete` is available only when the expected set is non-empty and every expected imported sample verifies exactly.

## HealthKit source constraint

Task 6 named the identity query `samplesAuthoredByThisApp`. Task 7 tightens the live implementation so it combines the external-UUID metadata predicate with a current-source predicate using `HKSource.default()`. This prevents a matching metadata UUID written by another source from satisfying BioMIR Backfill verification.

## Audit behavior

Verification failures append `VERIFICATION_FAILED` evidence to the run-scoped append-only audit ledger. Successful verification does not rewrite prior `IMPORTED` evidence.

The audit exporter writes a local directory containing:

- `manifest.json`
- `mapping-version.txt`
- `audit-ledger.jsonl`
- `verification.json`
- `SHA256SUMS.json`

`SHA256SUMS.json` contains SHA-256 hashes of the four evidence artifacts. Only ledger records for the verification run are exported.

## Ruling — async exporter interface

The original implementation plan specified `AuditExporter.export(manifest:ledger:verification:) throws -> URL`. Task 6 implemented `AuditLedger` as an actor. Reading run-scoped records therefore requires actor isolation. Task 7 uses `async throws -> URL` rather than bypassing Swift concurrency safety. This is an implementation-plan correction; it does not change the intended audit artifact.

## TDD evidence

RED was established before Task-7 production types existed: the portable harness failed because `VerificationModels.swift` and `VerificationEngine.swift` were absent.

GREEN portable behavior requires:

- exact expected/observed sample → verified complete
- missing expected sample → verification failed
- no HealthKit write path from verification

The authoritative Apple-framework and exporter gate remains macOS/Xcode XCTest.
