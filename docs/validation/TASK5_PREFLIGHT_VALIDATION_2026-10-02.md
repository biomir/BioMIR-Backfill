# Task 5 — Collision-Safe Preflight Validation

**Date:** 2026-10-02  
**Status:** IMPLEMENTED; macOS/Xcode validation pending

## Scope

Task 5 introduces the deterministic preflight boundary used before any HealthKit write:

- versioned import manifest;
- source-file SHA-256 binding;
- schema SHA-256 binding;
- parser/mapping/app/build/OS provenance;
- explicit read-visibility warning;
- per-candidate write-authorization gate;
- per-day/type visible-collision query;
- missing and explicit-zero dispositions without Health queries;
- existing visible Apple Health data wins;
- no writes occur during preflight.

## Controlled dispositions exercised

- `ELIGIBLE`
- `SKIPPED_EXISTING`
- `SKIPPED_MISSING`
- `SKIPPED_ZERO_POLICY`
- `AUTHORIZATION_BLOCKED`

Remaining audit dispositions are reserved for later import/verification tasks.

## Critical source-integrity gate

The reviewed manifest stores the selected source file SHA-256. Before import, Task 6 must recompute the current file fingerprint and invoke `SourceIntegrityGate.assertUnchanged`. A mismatch hard-fails rather than silently importing a file different from the one reviewed during preflight.

## HealthKit privacy limitation

An `.unverifiable` read state remains explicit. A clean visible query means only that no conflict was visible to BioMIR Backfill; it is not proof that Apple Health contains no record.

## Validation gates

1. `python3 tools/validate_task5.py`
2. portable Swift preflight harness
3. Xcode simulator XCTest suite via `./tools/verify_task5_macos.sh`

No personal health data is included in the repository or test fixtures.
