# BioMIR Backfill — Validation Protocol v0.1

**Status:** PRE-IMPLEMENTATION BASELINE  
**Date:** 2026-10-02

## Objective

Demonstrate that BioMIR Backfill deterministically parses, maps, screens, imports, and verifies historical nutrition data without deleting or replacing unrelated Apple Health records.

## Validation phases

### Phase 0 — Static design controls
- Approved intended use exists.
- Approved design specification exists.
- Mapping registry is versioned.
- Regulatory-readiness boundaries are documented.
- No implementation begins before the implementation plan is approved.

### Phase 1 — Pure deterministic components
Validate without HealthKit:
- CSV parser;
- alias/schema registry;
- source fingerprinting;
- date parsing;
- timezone/day interval construction;
- unit conversions;
- mapping engine;
- missing/zero distinction;
- manifest generation;
- audit ledger hashing.

Acceptance: all unit tests pass with deterministic fixtures.

### Phase 2 — HealthKit gateway integration
On a physical iPhone using controlled synthetic fixtures:
- HealthKit availability;
- read/write authorization;
- write-status checks;
- existing-sample queries;
- quantity/unit correctness;
- metadata round-trip;
- limited visibility handling.

Acceptance: observed behavior matches documented gateway contract.

### Phase 3 — Collision protection
Create controlled existing nutrition samples, then run preflight.

Acceptance:
- visible existing day/type slots are `SKIPPED_EXISTING`;
- absent slots are `ELIGIBLE`;
- no writes occur during preflight.

### Phase 4 — Import and batch recovery
Import controlled fixtures in bounded batches.

Test:
- normal completion;
- forced app termination mid-run;
- reopen/resume;
- repeated import.

Acceptance:
- successful batches remain intact;
- no deletion occurs;
- resume writes only missing records;
- repeat import does not reproduce application-authored records.

### Phase 5 — Post-write verification
For every written fixture sample, re-query and reconcile:
- type;
- value;
- unit;
- date interval;
- external identifier;
- provenance metadata.

Acceptance: planned/written/retrieved counts reconcile exactly.

### Phase 6 — Historical personal dataset dry run
Source:
- 1,400 daily rows;
- 2021-03-11 through 2025-01-08;
- nutrition-only controlled mapping.

Before any write:
- parse all rows;
- produce mapping report;
- produce collision preflight;
- produce eligible/skip/reject counts;
- manually review unsupported fields;
- confirm Health permissions.

Acceptance: no write until preflight is explicitly reviewed.

### Phase 7 — Historical personal dataset import
Import only after Phase 6 approval.

Acceptance:
- zero delete/replace calls;
- all successful writes verified;
- all failures enumerated;
- final audit bundle reconciles counts.

### Phase 8 — App Store readiness
Before public distribution:
- current iOS/HealthKit compatibility regression;
- privacy policy review;
- purpose-string review;
- App Store metadata review;
- intended-use/regulatory review;
- clean-install test;
- limited-history authorization test;
- source-file error handling;
- accessibility/usability pass.

## Stop conditions

Stop import immediately if:
- source hash changes after preflight;
- mapping version changes;
- schema differs from reviewed preflight;
- authorization is materially narrower than expected;
- verification mismatch occurs;
- unexpected unit/type behavior occurs;
- audit ledger cannot be persisted;
- HealthKit returns an unclassified error.

## Evidence artifacts

Preserve:
- test logs;
- screenshots where relevant;
- device/iOS/build information;
- fixture hashes;
- source hash;
- mapping version;
- import manifest;
- audit ledger;
- verification report;
- defect/deviation record.
