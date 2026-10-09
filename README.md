# BioMIR Backfill

A free companion utility designed to bring compatible historical nutrition CSV data into Apple Health. Useful when nutrition logs were not synced, or when moving from another platform with an export that can be converted to the supported schema.

**Current availability: source code for developer installation.** No App Store, TestFlight, or ready-to-install binary is provided here. The included physical-device validation report remains pending; public end-user release is not claimed.

## How it works

Select a compatible CSV, review the mapped nutrients and dates, authorize Apple Health access, review collision preflight, explicitly confirm the import, then inspect verification and export the local audit bundle. BioMIR Backfill writes the authorized history; BioMIR reads Apple Health for longitudinal analysis. No BioMIR analytical engine is included.

Processing and audit storage are local. No account, backend, or analytics SDK is required by the app. Apple Health remains subject to your device and iCloud settings.

## CSV compatibility

UTF-8 CSV with a `Date` column using `YYYY-MM-DD`, one unique daily row per date, and exact supported nutrient column names and units. See [nutrition mappings](docs/mapping/NUTRITION_MAPPING_v0.1.csv) and [header-only template](samples/nutrition-template.csv). Blank values remain missing; explicit zeros are distinguished and skipped under the current policy. Do not fill missing values with invented zeros.

Supported fields include dietary energy, protein, fats, fiber, sugar, sodium, other mapped minerals/vitamins, and water. Arbitrary third-party export schemas are not accepted automatically. A separate controlled Carb Manager total-carbohydrate profile exists; Net Carbs alone is not Apple Health total carbohydrate. See [limitations](docs/release/KNOWN_LIMITATIONS_v0.1.md).

Daily aggregates use noon in the device-local timezone as a date anchor, not an observed meal time. Check the timezone against the source history before importing. Visible existing Health records take precedence; unavailable read access means global duplicate absence cannot be proven.

## Install from source

Requires macOS with Xcode, an iPhone running iOS 17 or later, and Apple development signing. Open `BioMIRBackfill.xcodeproj`, select your signing team and an available bundle identifier, then build for your iPhone. Review the [device validation runbook](docs/validation/TASK9_DEVICE_VALIDATION_RUNBOOK_2026-10-02.md) before writing personal history. A simulator cannot establish actual HealthKit write behavior.

The project contains a narrowly constrained legacy timestamp-recovery control. It is not a general rollback and is not part of ordinary import; do not use it for a new migration.

## Status and documentation

[Validation report](docs/validation/VALIDATION_REPORT_v0.1.md) · [Development documentation](docs/DEVELOPMENT_STATUS_ORIGINAL.md) · [Mapping registry](docs/mapping/NUTRITION_MAPPING_v0.1.csv).

Only templates and synthetic fixtures belong in Git. Keep personal nutrition exports, Apple Health exports, signing credentials, and local audit bundles private.

## Rights

Copyright © 2026 BioMIR. All rights reserved. Source is published for inspection; no open-source reuse license has been selected. Free availability is not a grant to redistribute or modify the software.
