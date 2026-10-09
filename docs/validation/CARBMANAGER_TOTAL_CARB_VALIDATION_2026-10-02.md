# BioMIR Backfill — Carb Manager Total-Carbohydrate Extension v1

Date: 2026-10-02

## Scope

This extension adds one controlled, separate mapping profile for historical **total carbohydrate** reconstruction from Carb Manager. It does not modify the validated `nutrition-v0.1` registry and does not reinterpret `Net Carbs (g)` as Apple Health total carbohydrate.

## Controlled mapping

- Profile version: `carbmanager-total-carb-v1`
- Import CSV schema: exactly `Date` + `Carb Manager Total Carbohydrates (g)`
- Apple Health type: `dietaryCarbohydrates`
- Unit: grams
- Transformation ID: `carbmanager-total-carb-reconstruction-v1`
- Reconstruction formula: `Net Carbs + Fiber + Sugar Alcohols + Allulose`

The profile is activated only when the exact two-column schema is present. If the reconstructed-carb column appears beside any additional field, the mapping engine produces no candidates for that file. This prevents accidental re-import of fiber or any other previously imported nutrient.

## Source evidence used for the 2021-03-11 through 2025-01-08 reconstruction

- Carb Manager report: `macronutrients_20200926-20261002_f86af46a-ade3-43d9-be01-3b6a63963155.csv`
- Carb Manager report SHA-256: `2db22dc2bc66b4894901de83bf0da6647bbb1f013b9e62cc0d0e90de5df5f3b0`
- Previously validated nutrition/missingness source: `BioMIR_HK_Nutrition_MissingOnly.csv`
- Missingness source SHA-256: `066e6b96850f4f6709321ac92ff081b347ccf278aff4e9f335ff6151581525d2`

The Carb Manager export explicitly contains `Net Carbs (g)`, `Fiber (g)`, `Sugar Alcohols (g)`, and `Allulose (g)`. Allulose is 0.0 on every date in the 1,400-day target window, but the reconstruction still includes the Allulose term so the transformation matches the documented Carb Manager relationship rather than assuming it away.

Carb Manager zero-fills the five previously established no-log dates. The generator therefore uses the already validated nutrition source as the missingness authority and keeps these dates blank:

- 2023-09-26
- 2023-09-27
- 2023-09-28
- 2023-09-29
- 2023-09-30

## Generated import artifact

- Filename: `BioMIR_CarbManager_TotalCarbohydrates_20210311_20250108.csv`
- Rows: 1,400
- Importable observed values: 1,395
- Missing values: 5
- Explicit zero values: 0
- Allulose nonzero days: 0
- Observed total-carbohydrate range: 2.00–462.16 g/day
- Output SHA-256: `d842d227e94f72cd9e57072e867513d6d13322780709431dbf47b80da07ef815`
- Reconstruction evidence SHA-256: `334b35dd45fe6cca2091b6876e79f628b85a63910ea2df707840965b11b6747d`

The generated personal CSV, evidence CSV, provenance JSON, raw Carb Manager report, and missingness source remain outside the repository.

## Validation gates

1. `nutrition-v0.1` remains exactly 31 supported mappings and still contains no `.dietaryCarbohydrates` mapping.
2. `Net Carbs (g)` remains explicitly unsupported by `nutrition-v0.1`.
3. The carb profile resolves only to `.dietaryCarbohydrates`.
4. Mixed-schema files containing the reconstructed-carb column are blocked from producing candidates.
5. Generator test must prove inclusion of all four formula terms, including a nonzero synthetic Allulose case.
6. Generator must preserve the controlled missingness mask rather than treating Carb Manager's zero-filled no-log dates as observed zeros.
7. Current HealthKit SDK must resolve `.dietaryCarbohydrates` for the new profile.
8. Full existing Tasks 1–8 simulator/XCTest regression must remain green.
9. Physical-device preflight is required before writing the 1,395 samples.
10. Post-write exact verification must report 1,395 verified / 0 failed before this extension is closed.

## Expected device preflight for this user's current Apple Health state

If no historical total-carbohydrate samples are visible in Apple Health:

- Eligible: 1,395
- Existing visible: 0
- Missing: 5
- Zero-policy skips: 0
- Authorization blocked: 0
- Unsupported fields: 0

Any deviation must be reviewed before import. Existing visible samples win and must not be overwritten.


## Physical-device parser finding before write

The first two-row smoke review correctly fingerprinted the intended file (`e7b45ac11b84…`) but displayed 0 rows, 3 unsupported fields, and `nutrition-v0.1`. No preflight or HealthKit carbohydrate write was performed.

Root cause was reproduced with the exact CRLF byte pattern: Swift iterates CRLF as one `Character`, so the original tokenizer failed to terminate records. The controlled correction explicitly handles the CRLF grapheme and adds both XCTest and portable CRLF regression coverage.

This is a parser-only correction. The generated carbohydrate values, reconstruction formula, source fingerprints, mapping profile, HealthKit identifier, collision policy, append-only behavior, provenance, and verification semantics are unchanged.

## Status

**CRLF PARSER CORRECTION IMPLEMENTED LOCALLY; MAC/XCODE REGRESSION AND PHYSICAL-DEVICE SMOKE RETEST PENDING.**
