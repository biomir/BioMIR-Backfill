# BioMIR Backfill — Carb CSV CRLF Hotfix Validation

Date: 2026-10-02

## Observed physical-device failure

The first carbohydrate smoke CSV reached Review with:
- file fingerprint prefix `e7b45ac11b84…`
- Rows: 0
- Supported mappings: 0
- Unsupported fields: 3
- Mapping: `nutrition-v0.1`

No carbohydrate preflight or HealthKit write was performed.

## Source-file integrity

The screenshot fingerprint prefix exactly matches the generated smoke CSV SHA-256:

`e7b45ac11b843eb5b9211b360cf6ff839e3afb7fc267b0fc9bd4ca129bea52ba`

The smoke CSV bytes are valid two-column CRLF CSV:

- header: `Date,Carb Manager Total Carbohydrates (g)`
- 2021-03-11: 59.93 g
- 2021-03-12: 37.93 g

## Root cause

Swift `Character` segmentation treats the CRLF scalar pair (`\r\n`) as a single grapheme cluster. The original `CSVParser.tokenize` switch handled standalone `\r` and standalone `\n`, but not the combined CRLF `Character`. Consequently, CRLF separators were appended into field text instead of terminating records.

The defect was reproduced before the fix with the exact CRLF byte pattern. The parser returned:

`["Date", "Carb Manager Total Carbohydrates (g)\r\n2021-03-11", "59.93\r\n2021-03-12", "37.93"]`

and zero data rows, exactly explaining the physical-device Review screen.

## Controlled correction

`CSVParser.tokenize` now explicitly handles the CRLF grapheme as a record terminator. No mapping, HealthKit, provenance, collision, write, verification, or carbohydrate reconstruction logic changed.

Permanent regression coverage was added:
- XCTest CRLF parsing test using the carbohydrate smoke schema.
- Portable carb-profile harness now uses CRLF input.

## Local post-fix evidence

The exact generated smoke CSV was parsed after the correction with:
- Headers: `Date`, `Carb Manager Total Carbohydrates (g)`
- Rows: 2
- Mapping: `carbmanager-total-carb-v1`
- Candidates: 2
- Unsupported: 0
- Values: 59.93 g, 37.93 g

Local portable validation: PASS.

## Remaining gate

Full Mac/Xcode regression must be rerun after applying this hotfix. The corrected app must then be rebuilt and installed on the physical iPhone before repeating the two-record smoke Review/Preflight.

Physical-device carbohydrate import remains PENDING.
