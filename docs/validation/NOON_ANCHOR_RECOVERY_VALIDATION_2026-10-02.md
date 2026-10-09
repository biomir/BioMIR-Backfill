# BioMIR Backfill — Historical Daily-Aggregate Noon-Anchor Recovery

Date: 2026-10-02
Status: **Mac/device deletion + re-import pending**

## Observed integration defect

The Apple Health source data were not duplicated. A representative comparison showed:

- 2021-08-22 Dietary Energy in Apple Health: **2,930 kcal**
- 2021-08-23 Dietary Energy in Apple Health: **3,056 kcal**
- BioMIR value displayed for 2021-08-22: **5,986 kcal**

`2,930 + 3,056 = 5,986`, demonstrating that the historical full-day representation can cause the adjacent midnight sample to overlap BioMIR's existing nutrition day query.

## Design decision

Production BioMIR remains unchanged because the observed issue is specific to the representation selected by BioMIR Backfill for historical daily aggregates, not normal event-like HealthKit nutrition data.

BioMIR Backfill now stores every imported historical daily aggregate at a canonical local-noon point:

`startDate == endDate == 12:00 local time on source calendar date`

The noon timestamp is an indexing anchor only. It must not be interpreted as the time food or water was consumed.

## Provenance

Corrected imports add controlled metadata:

- key: `co.biomir.backfill.time_anchor_policy`
- value: `daily-aggregate-noon-v1`

Source file SHA-256, source date, row identity, mapping version, transformation, batch ID, and deterministic external UUID remain controlled as before.

## One-time deletion recovery

Normal imports remain append-only. The recovery action is a narrowly scoped exception.

It targets only legacy objects satisfying all of the following:

1. source = current BioMIR Backfill HealthKit source,
2. classification = `historical-user-controlled-import`,
3. mapping version in `{nutrition-v0.1, carbmanager-total-carb-v1}`,
4. start date within `[2021-03-11 00:00, 2025-01-09 00:00)`,
5. positive duration (`startDate < endDate`),
6. no `time_anchor_policy` metadata.

Corrected noon-point samples are therefore excluded from subsequent recovery runs.

## Expected recovery count

Validated source accounting:

| Source | Eligible imported samples |
|---|---:|
| `BioMIR_HK_Nutrition_MissingOnly.csv` | 42,217 |
| `BioMIR_CarbManager_TotalCarbohydrates_20210311_20250108.csv` | 1,395 |
| **Expected legacy deletion total** | **43,612** |

The original 31-field source retains 155 missing cells and 1,028 explicit-zero-policy skips. The carb source retains five missing dates and zero explicit-zero skips.

A physical-device deletion count other than **43,612** is a hard stop before re-import.

## Re-import sequence

After an exact 43,612-sample recovery deletion:

1. Re-import the exact original 31-field source.
2. Require preflight = 42,217 eligible / 155 missing / 1,028 zero-policy skips / 0 authorization blocked.
3. Require final verification = 42,217 verified / 0 verification failures.
4. Re-import the exact carb-only source.
5. Require preflight = 1,395 eligible / 5 missing / 0 zero-policy skips / 0 authorization blocked.
6. Require final verification = 1,395 verified / 0 verification failures.
7. Verify representative Apple Health samples show a 12:00 PM point timestamp and source BioMIR Backfill.
8. Refresh/relaunch BioMIR and verify 2021-08-22 Dietary Energy = 2,930 kcal, not 5,986 kcal.
9. Spot-check carbohydrate and sodium on multiple adjacent dates.

## Source fingerprints

- Original 31-field source SHA-256: `066e6b96850f4f6709321ac92ff081b347ccf278aff4e9f335ff6151581525d2`
- Carb source SHA-256: `d842d227e94f72cd9e57072e867513d6d13322780709431dbf47b80da07ef815`

## Pending evidence

- Mac/Xcode compile and XCTest after applying this change.
- Physical-device legacy deletion count.
- Physical-device corrected re-import verification bundles.
- BioMIR post-repair spot-checks.
