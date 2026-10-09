# BioMIR Backfill

**Purpose:** A standalone, local-only iOS companion for importing compatible historical wellness data into Apple Health with deterministic mapping, collision preflight, provenance, verification, and auditability.

## Product boundary

BioMIR Backfill is deliberately separate from BioMIR.

- **BioMIR Backfill:** writes user-authorized historical data to Apple Health.
- **Apple Health:** remains the shared personal health-data repository.
- **BioMIR:** remains read-only and performs deterministic longitudinal analytics.

No BioMIR analytical engines are linked into the Backfill target.

## Initial scope

Version 1 is **nutrition-only**. The first validated use case is a 1,400-day historical nutrition backfill covering 2021-03-11 through 2025-01-08.

## Safety invariants

1. Normal imports are append-only.
2. No general-purpose HealthKit delete/replace path. A one-time provenance- and interval-constrained timestamp-recovery operation is the only deletion exception.
3. Existing visible Apple Health data wins.
4. Unsupported or semantically ambiguous fields are rejected rather than inferred.
5. Every transformation is deterministic and versioned.
6. Every import is fingerprinted, auditable, and verified after writing.
7. The app remains local-only: no backend, analytics SDK, ad SDK, account system, or cloud health-data storage.

## Regulatory posture

The present intended use is a personal wellness-data transfer utility. The project is **not represented as FDA-cleared, CLIA-certified, or SaMD**. It is structured for auditability, validation, provenance, risk management, and change control so future regulated-use assessment is feasible rather than retrofitted.

Read `docs/regulatory/REGULATORY_READINESS.md` before changing scope.

## Key documents

- Design spec: `docs/superpowers/specs/2026-10-02-biomir-backfill-design.md`
- Implementation plan: `docs/superpowers/plans/2026-10-02-biomir-backfill-implementation.md`
- Regulatory posture: `docs/regulatory/REGULATORY_READINESS.md`
- Validation protocol: `docs/validation/VALIDATION_PROTOCOL_v0.1.md`
- Nutrition mapping registry: `docs/mapping/NUTRITION_MAPPING_v0.1.csv`
- Project context for future agents: `PROJECT_CONTEXT.md`

## Status

**Tasks 1–7 validated. Task 8 guarded end-to-end SwiftUI workflow implemented; Mac/Xcode validation pending.**

Implementation must follow the approved plan and validation gates.

## Task 7 status

Post-write verification and local audit export are implemented behind the existing controlled interfaces. Verification re-queries only current-app samples for the imported deterministic external identities and requires an exact type/value/unit/date/identity/provenance match before reporting Verified Complete. Audit export is local and includes SHA-256 hashes. Physical-device bulk import remains gated until later validation tasks.


## Task 8 status

The four-stage SwiftUI workflow is now wired through `ImportViewModel`: source selection, deterministic review, Health authorization/preflight, explicit import confirmation, post-write verification, and local audit export. SwiftUI contains no direct HealthKit or domain-engine calls. Personal 1,400-day device validation remains gated to Task 9.

## Task 9 physical-device validation

Task 8 is the validated functional-app baseline. Task 9 is evidence-only physical-device validation. Use `tools/task9_prepare_validation.py` to validate the personal 1,400-day source and generate a local two-row smoke fixture outside the repository. Execute the three gated device sequence in `docs/validation/TASK9_DEVICE_VALIDATION_RUNBOOK_2026-10-02.md`. Never commit personal CSV/XML/Health exports or locally generated smoke inputs.

## Carb Manager total-carbohydrate extension

A separate controlled profile, `carbmanager-total-carb-v1`, supports a carb-only CSV with exactly `Date` and `Carb Manager Total Carbohydrates (g)`. The value is reconstructed from Carb Manager as Net Carbs + Fiber + Sugar Alcohols + Allulose under transformation `carbmanager-total-carb-reconstruction-v1`. This profile is isolated from `nutrition-v0.1`: Net Carbs remains unsupported there, and mixed-schema files containing the reconstructed-carb field are blocked from producing carb-profile candidates. Use `tools/build_carbmanager_total_carbs.py` only with the original Carb Manager report plus a validated missingness source, and keep generated personal CSV/evidence files outside the repository.

### Historical daily-aggregate timestamp policy

BioMIR Backfill represents source rows that are daily historical aggregates as a canonical **12:00 PM local point sample** in Apple Health. The timestamp is an indexing anchor, not an observed consumption time. Corrected samples carry `co.biomir.backfill.time_anchor_policy = daily-aggregate-noon-v1`.

Normal imports remain append-only. A one-time, provenance-constrained recovery control exists only to remove the legacy 2021-03-11 through 2025-01-08 full-day BioMIR Backfill samples before controlled re-import under the noon-anchor policy. It does not provide a general-purpose HealthKit delete function.
