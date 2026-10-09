# BioMIR Backfill — Project Context

## Why this project exists

BioMIR's longitudinal value depends on Apple Health containing sufficient historical data. Prospective users may already possess legitimate years of historical nutrition/wellness data in spreadsheets or exports that Apple Health does not contain. Without a safe ingestion pathway, their BioMIR trajectory effectively starts when Apple Health collection starts.

BioMIR Backfill addresses that onboarding pain point.

## Architectural rule

**BioMIR owns analysis and remains read-only. BioMIR Backfill owns historical ingestion. Apple Health is the boundary between them.**

Historical source file
→ BioMIR Backfill
→ Apple Health
→ BioMIR
→ deterministic longitudinal analysis

Never create a direct BioMIR Backfill → BioMIR data pipe.

## Initial validated dataset

- 1,400 consecutive daily records
- 2021-03-11 through 2025-01-08
- Historical source: Biometrics/Keto longitudinal metadata
- Initial import scope: nutrition only
- Existing Apple Health export dated 2025-06-17 showed zero standard `HKQuantityTypeIdentifierDietary...` records over the historical period
- A future production preflight must query Apple Health directly rather than rely on that static export

## Explicit non-goals for v1

- No diagnostics
- No treatment recommendations
- No biological-age computation
- No laboratory-result interpretation
- No clinical-record writing
- No arbitrary HealthKit importer
- No Net Carbs → Total Carbohydrate inference
- No cloud processing
- No advertising or analytics SDKs
- No HealthKit delete/replace functionality

## Development posture

Treat mapping tables and transformation constants as controlled reagents:
- version them;
- test them;
- fingerprint them;
- record them in import manifests;
- require validation evidence for changes.

Preserve the distinction among:
- observed value;
- explicit zero;
- missing value.

Never silently coerce missing to zero.

## Regulatory posture

Current intended use is a personal health-data transfer utility, not a laboratory system or diagnostic/therapeutic software function. Maintain CLIA/SaMD/QMS readiness through traceability, deterministic processing, verification, validation, provenance, risk management, SBOM/dependency inventory, release manifests, and change control.

A change in intended use or claims requires regulatory reassessment before implementation.

## Agent instructions

Before implementation:
1. Read the approved design spec.
2. Read the implementation plan.
3. Read the regulatory-readiness document.
4. Follow TDD and the validation protocol.
5. Do not broaden scope without updating the spec and risk register.
6. Do not add third-party dependencies without documenting why Apple/Foundation frameworks are insufficient.
7. Never add HealthKit deletion or overwrite semantics.
