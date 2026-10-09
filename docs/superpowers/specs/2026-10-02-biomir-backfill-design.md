# BioMIR Backfill — Design Specification v1.0
**Date:** 2026-10-02  
**Status:** APPROVED

## 1. Purpose

BioMIR Backfill is a standalone iOS utility for transferring compatible user-owned historical wellness data from local structured files into Apple Health.

Its initial purpose is to solve a longitudinal-data onboarding problem: a user may possess years of historical nutrition records that are absent from Apple Health, preventing those records from participating in longitudinal applications such as BioMIR.

BioMIR Backfill is separate from BioMIR. BioMIR remains read-only with respect to Apple Health.

## 2. Intended use

> BioMIR Backfill allows a user to review, map, validate, and transfer compatible historical wellness data that the user controls into Apple Health.

The application does not diagnose disease, recommend treatment, assess clinical risk, perform biological-age calculations, interpret laboratory results, or independently measure a biological variable.

It performs deterministic data operations only:

source parsing → semantic mapping → unit normalization → collision screening → authorized Health write → verification.

## 3. Regulatory-readiness posture

The present application is designed as a personal health-data transfer utility. It is not represented as FDA-cleared, CLIA-certified, or SaMD.

Nevertheless, development will preserve:
- requirements traceability;
- risk-based controls;
- deterministic transformations;
- configuration/change control;
- software verification and validation;
- release identification;
- provenance;
- auditability;
- defect traceability;
- reproducible validation evidence.

Any future diagnostic, therapeutic, laboratory, clinical decision-support, or regulated-use claim requires a new intended-use and regulatory assessment before implementation.

## 4. Apple Health compatibility

Use native HealthKit APIs only.

Production target requirements:
- HealthKit capability;
- `NSHealthShareUsageDescription`;
- `NSHealthUpdateUsageDescription`;
- no Clinical Health Records entitlement;
- explicit read/write authorization only for selected import types;
- write authorization status checked before saving;
- `HKQuantitySample` and compatible `HKUnit` values;
- compatibility validation on physical iPhone hardware.

HealthKit privacy limitations must be disclosed: denied read access can appear as no data, so preflight can report only records visible to the app.

## 5. Initial data scope

Version 1 is nutrition-only.

Supported values require exact semantic correspondence with Apple Health nutrition quantity types.

No semantic coercion:
- Net Carbs is not Total Carbohydrate.
- Derived ratios are not HealthKit measurements.
- Unsupported fields are ignored/rejected, never forced into a superficially similar type.

## 6. Data integrity

Preserve three states:
- observed numeric value;
- explicit zero;
- missing.

Do not silently convert missing to zero.

Every deterministic transformation records:
- original value;
- original unit;
- normalized value;
- normalized Health unit;
- transformation ID;
- transformation version.

## 7. Daily aggregate time semantics

Historical daily aggregates establish a calendar day but not meal time.

Do not fabricate breakfast/lunch/dinner timestamps.

Represent each daily aggregate using a calendar-day interval derived with `Calendar` and the selected source timezone:
- start: local start of source day;
- end: local start of next source day.

Validate Apple Health display/aggregation behavior on-device before bulk import.

## 8. Collision protection

Production code is append-only.

No HealthKit delete/replace path exists.

For each visible `calendar day × Health type`:
- existing visible sample → `SKIPPED_EXISTING`
- no visible sample → `ELIGIBLE`
- authorization unavailable → `AUTHORIZATION_BLOCKED`
- invalid mapping/value/unit → rejected

Existing visible data always wins.

The app must never claim universal duplicate freedom; it may state only that no conflict was visible to the app.

## 9. Provenance

Use Apple-defined metadata where appropriate plus controlled app metadata.

Record:
- import batch UUID;
- schema version;
- mapping version;
- source calendar date;
- canonical source field;
- source unit;
- transformation ID;
- source-file fingerprint;
- historical-import classification.

Generate a deterministic external identity from controlled inputs such as source-file hash + source row identity + canonical Health type + source date + mapping version.

## 10. Source integrity

Immediately fingerprint selected source bytes using SHA-256.

Manifest records:
- filename;
- SHA-256;
- file size;
- row count;
- encoding;
- date range;
- source timezone;
- column schema;
- schema hash;
- parser version;
- mapping version;
- app version/build;
- iOS version;
- import timestamp.

No source upload to a server.

## 11. Audit ledger

Each candidate row/type receives exactly one disposition:

- `IMPORTED`
- `SKIPPED_EXISTING`
- `SKIPPED_MISSING`
- `SKIPPED_ZERO_POLICY`
- `UNSUPPORTED`
- `REJECTED_RANGE`
- `REJECTED_UNIT`
- `REJECTED_MAPPING`
- `AUTHORIZATION_BLOCKED`
- `WRITE_FAILED`
- `VERIFICATION_FAILED`

Exportable audit bundle contains manifest, mapping version, summary counts, disposition log, build information, source hash, audit hashes, and verification result.

## 12. Separation of concerns

Planned components:
- `SourceDocumentService`
- `CSVParser`
- `SchemaRegistry`
- `MappingEngine`
- `HealthStoreGateway`
- `PreflightEngine`
- `ImportCoordinator`
- `ProvenanceService`
- `AuditLedger`
- `VerificationEngine`

No UI component performs Health writes directly.

No BioMIR analytical engine is linked into the companion target.

## 13. Transaction/recovery

Write bounded batches, initial target 100–250 samples.

Every batch has an ID, planned range, start time, write status, and verification status.

Recovery is forward-only. Never roll back successful imports by deleting Health records.

## 14. Verification

A HealthKit save callback is not sufficient.

After each batch, query application-authored samples and reconcile:
- expected Health type;
- normalized value/unit;
- date interval;
- external identity;
- provenance metadata.

Do not display `Verified Complete` unless planned/written/retrieved counts reconcile.

## 15. Validation strategy

Maintain requirement → risk → control → implementation → test → result traceability.

Core tests:
- CSV grammar/malformed source;
- schema aliases;
- dates/timezones/DST;
- unit conversions;
- semantic mappings;
- unsupported fields;
- NaN/infinity/range rejection;
- missing vs zero;
- authorization states;
- limited historical visibility;
- collision screening;
- repeated import;
- batch interruption/resume;
- post-write verification;
- audit integrity;
- release regression.

## 16. Privacy/cybersecurity

Initial release:
- no account;
- no backend;
- no remote database;
- no advertising SDK;
- no third-party analytics SDK;
- no generative AI;
- no network requirement for import;
- no iCloud health-data storage.

Prefer Apple/Foundation frameworks and minimize dependencies.

## 17. Product presentation

Proposed name: **BioMIR Backfill**

Proposed subtitle: **Bring your history to Apple Health**

Core message:

> Import compatible historical wellness data into Apple Health with transparent mapping, provenance, preflight review, and verification.

## 18. Future extension gates

Nutrition is the initial controlled scope.

Any added data family requires:
- mapping specification;
- risk review;
- validation fixtures;
- traceability updates;
- release validation.

Clinical records remain out of scope for writing.

## 19. Release artifacts

Each controlled release preserves:
- Intended Use statement
- Software Requirements Specification
- Data Mapping Specification
- Risk Register
- Requirements Traceability Matrix
- HealthKit Compatibility Matrix
- Verification Protocol
- Verification Report
- Known Limitations
- Change Log
- source-control tag
- build identifier
- mapping/schema version
- dependency inventory/SBOM
- release manifest

## 20. v1 acceptance criteria

Personal deployment requires:
- deterministic parse of the 1,400-day source;
- approved mappings only;
- unsupported fields rejected;
- minimum required Health permissions only;
- no delete/replace code;
- visible collision preflight;
- authorization limitations disclosed;
- provenance on every write;
- SHA-256 source fingerprint;
- recoverable bounded batches;
- post-write verification;
- repeat-import protection for own samples;
- reconciled audit report;
- no BioMIR modification.

App Store release requires an additional release-validation cycle, privacy-policy review, current-SDK compatibility validation, App Store metadata review, and intended-use/regulatory review.
