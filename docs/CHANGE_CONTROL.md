# Change Control

## Baseline — 2026-10-02

- Design Specification v1.0 approved.
- Implementation Plan v1.0 created.
- Nutrition Mapping v0.1 established as controlled documentation.
- Validation Protocol v0.1 established.
- Regulatory-readiness posture established.
- No production implementation code exists yet.

## Rule

Any change to intended use, supported data family, mapping semantics, transformation constants, HealthKit write behavior, provenance, or audit policy requires:
1. documented rationale;
2. risk review;
3. version update;
4. traceability update;
5. test/validation update;
6. change-log entry.

## Task 1 scaffold — 2026-10-02

- Added standalone `BioMIRBackfill.xcodeproj`.
- Added SwiftUI application shell with four guarded stages.
- Added HealthKit entitlement without Clinical Health Records access.
- Added Health read/update privacy purpose strings.
- Added architecture-boundary XCTest.
- Added portable structural validation and macOS build/XCTest verification script.
- No HealthKit read/write implementation exists yet.
- Final Task 1 platform gate remains `./tools/verify_task1_macos.sh` on macOS/Xcode.

## Task 2 implementation baseline — 2026-10-02

- Added deterministic UTF-8/BOM-aware CSV parser.
- Added strict ISO source-date parsing and duplicate-date rejection.
- Added explicit missing / zero / numeric observation states.
- Added DST-safe calendar-day interval construction.
- Added exact-byte SHA-256 source fingerprinting using CryptoKit.
- Added local source-document loader with security-scoped URL handling.
- Added Task-2 XCTest coverage and portable validation tooling.
- No HealthKit read/write behavior was introduced in Task 2.
- macOS/Xcode Task-2 verification remains a release gate before Task 3.

## Task 3 — 2026-10-02

- Added controlled nutrition mapping models, `NutritionMappingRegistry`, and `MappingEngine`.
- Locked registry version to `nutrition-v0.1`.
- Added 31 supported nutrient mappings and 9 explicit unsupported mappings.
- Added a machine drift check between `NUTRITION_MAPPING_v0.1.csv` and Swift registry code.
- Preserved `Net Carbs (g)` as semantically distinct from Apple Health total carbohydrate.
- Added versioned water conversion `water-us-fl-oz-to-ml-v1` at 236.5882365 mL per 8-US-fl-oz glass.
- Added mapping tests and portable behavior validation.
- No HealthKit persistence behavior added.

## Task 4 — 2026-10-02

- Added explicit HealthKit gateway boundary.
- Added separate write-authorization and read-visibility models.
- Preserved append-only architecture: no HealthKit delete/replace API exists.
- Added current-SDK ruling: Xcode 26.3/iOS 26.2 cannot positively inspect limited-history authorization introduced with iOS 27; read visibility is therefore conservatively `.unverifiable` until a controlled SDK-27 update.
- Added simulator/XCTest validation gate and deferred real authorization/write validation to physical-device validation.


## Task 4 validation closure — 2026-10-02

- Task 4 simulator/XCTest validation passed on the user Mac.
- Validation harness corrections were isolated from production HealthKit code and recorded separately.
- Task 4 is closed at validated commit lineage `496ccf1` + validation-harness correction `b37698d`.

## Task 5 — 2026-10-02

- Added versioned import manifest with source, schema, parser, mapping, build, OS, timezone, and date-range provenance.
- Added hard source-fingerprint recheck gate for import-time change detection.
- Added collision-safe `PreflightEngine` with visible-existing-data precedence.
- Added explicit missing, zero-policy, authorization-blocked, existing, and eligible dispositions.
- Preserved HealthKit read-visibility uncertainty in the preflight report and warning state.
- Added Task-5 XCTest coverage and portable validation harness.
- No HealthKit write occurs during preflight.

## Task 5 validation closure — 2026-10-02

- Task 5 portable preflight and simulator/XCTest validation passed on the user Mac.
- Collision-safe preflight is closed at commit `88f8397`.
- The working tree was clean before Task 6 began.

## Task 6 — 2026-10-02

- Added deterministic provenance/external identity service.
- Added append-only local audit ledger and append-only batch journal.
- Added controlled batch coordinator with default 200 and allowed configured range 100...250.
- Added immediate pre-write source SHA-256 and write-authorization rechecks.
- Added deterministic app-authored identity lookup as a repeat-import guard.
- Added forward-only interruption behavior: failed batches stop the run; recovery requires fresh preflight; no rollback/delete path exists.
- Added Task-6 XCTest and portable coordination coverage.
- Audit export hashing remains assigned to Task 7, where `AuditExporter` is created.
- macOS/Xcode Task-6 verification remains required before Task 7.

## 2026-10-02 — Task 7 post-write verification and hashed audit export

- Added exact post-write reconciliation for Task-6 imported samples.
- Added `ImportedSampleExpectation` evidence to `ImportResult` so verification compares the actual planned write contract against returned HealthKit samples.
- Extended `HealthSampleSummary` with the user-entered flag and controlled BioMIR Backfill string provenance metadata.
- Tightened app-authored HealthKit queries to require both deterministic external UUID metadata and the current `HKSource.default()` source.
- Added `VERIFIED` / `VERIFICATION_FAILED` reporting; `Verified Complete` requires a non-empty exact reconciliation with zero failures.
- Added run-scoped local audit export with manifest, mapping version, JSONL audit ledger, verification report, and SHA-256 artifact hashes.
- Verification remains read-only and contains no delete, replacement, rollback, or HealthKit save operation.
- Ruling: `AuditExporter.export` is async because `AuditLedger` is actor-isolated.

## 2026-10-02 — Task 8 guarded four-stage import workflow

- Added `ImportViewModel` as the sole UI orchestration boundary for source intake, mapping, authorization, preflight, import coordination, verification, and audit export.
- Replaced the scaffold-only screen with the functional four-stage flow: Select Source → Review → Preflight → Results.
- Added source fingerprint/date/mapping review evidence and unsupported-field reasons.
- Added Health preflight counts and persistent read-visibility warning presentation.
- Added explicit user acknowledgment and confirmation before import.
- Added mandatory fresh preflight immediately before import; any changed preflight blocks the write and requires another review.
- Added a hard write gate when persistent local audit storage cannot initialize.
- Added post-write reconciliation/result presentation and local audit-bundle sharing.
- Added Task-8 view-model state-transition tests, portable workflow harness, structural boundary validator, and macOS/Xcode verification script.
- No BioMIR analytical module was linked and no mapping/write/verification semantics were changed.
- Physical-device personal-data validation remains assigned to Task 9.

## 2026-10-02 — Task 8 Swift 6 concurrency correction

- First macOS/Xcode Task-8 validation exposed a Swift 6 actor/sendability compile failure when the `@MainActor` view model passed its gateway into nonisolated async orchestration APIs.
- Root cause: `HealthStoreGateway` did not declare the cross-concurrency sendability required by its existing use.
- Added `Sendable` to the gateway protocol and checked `Sendable` conformance to `LiveHealthStoreGateway`; Apple SDK metadata declares `HKHealthStore` `Sendable`.
- Added test-only `@unchecked Sendable` to mutable fake gateways used by XCTest and portable harnesses.
- Strengthened Task-8 portable compilation with Swift 6 complete-concurrency checking.
- No HealthKit mapping, append-only behavior, collision policy, provenance, verification, or audit semantics changed.

## 2026-10-02 — Task 9 validation scaffolding

- Added physical-device validation runbook and explicitly pending validation-report template.
- Added known-limitations and HealthKit compatibility-matrix artifacts.
- Added local-only source/smoke-fixture preparation tool; personal health inputs are not committed.
- Added Task-9 privacy/claims validator and pre-device regression wrapper.
- No production application behavior, mapping, HealthKit write policy, or verification semantics changed.

## 2026-10-02 — BioMIR Backfill app-icon branding

- Added the user-supplied BioMIR logo as the BioMIR Backfill app icon without redesigning or recoloring the mark.
- Added a standard `Assets.xcassets/AppIcon.appiconset` with complete iPhone, iPad, and 1024×1024 marketing icon assets.
- App-icon PNGs are opaque 8-bit RGB and preserve the supplied artwork proportions on a square canvas.
- Wired `Assets.xcassets` into the application Resources phase and set `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` for app build configurations.
- Extended the Task-9 validator with app-icon catalog, dimension, opacity, and project-wiring checks.
- No HealthKit, parsing, mapping, preflight, import, provenance, verification, or audit behavior changed.

## 2026-10-02 — Carb Manager total-carbohydrate extension v1

- Added a separate controlled mapping profile `carbmanager-total-carb-v1`; the validated `nutrition-v0.1` registry remains unchanged at 31 supported mappings.
- Added one exact-schema mapping from `Carb Manager Total Carbohydrates (g)` to Apple Health `.dietaryCarbohydrates` in grams.
- Added transformation ID `carbmanager-total-carb-reconstruction-v1` for values reconstructed as Net Carbs + Fiber + Sugar Alcohols + Allulose.
- Added a hard schema-isolation rule: the carb profile maps only an exact two-column `Date` + reconstructed-total-carb CSV; mixed files produce no carb-profile candidates.
- Added a deterministic reconstruction tool using the fresh Carb Manager report plus the previously validated nutrition source as the missingness authority.
- Preserved five known no-log dates as missing rather than treating Carb Manager's report zeros as observed zero intake.
- Added profile isolation, builder, current-SDK identifier, and full regression validation gates.
- No deletion/replacement behavior was added and no already-imported nutrition type is re-written by this profile.

## 2026-10-02 — CSV CRLF tokenizer correction

- Physical-device carb smoke review exposed a parser defect before any carbohydrate write occurred: a CRLF CSV was interpreted as one record, producing 0 rows and bogus unsupported headers.
- Root cause: Swift `Character` segmentation treats the CRLF scalar pair as a single grapheme cluster, while `CSVParser.tokenize` handled only standalone `\r` and `\n` characters.
- Added an explicit CRLF branch that terminates the record without changing LF-only or standalone-CR behavior.
- Added permanent XCTest coverage using the exact two-row carbohydrate smoke schema and switched the portable carb-profile harness to CRLF input.
- The source fingerprint and carbohydrate reconstruction are unchanged; no HealthKit write occurred from the failed review screen.
- Full Mac/Xcode regression and a newly installed physical-device build are required before resuming the smoke test.


## 2026-10-02 — Historical daily-aggregate noon-anchor recovery

**Trigger:** Physical-device comparison showed that BioMIR's existing overlap-based nutrition reader can include the next day's boundary sample when BioMIR Backfill stores a historical daily aggregate as a midnight-to-next-midnight interval. Example: Apple Health stored 2,930 kcal on 2021-08-22 and 3,056 kcal on 2021-08-23; BioMIR displayed 5,986 kcal for 2021-08-22.

**Decision:** Preserve production BioMIR unchanged. Change BioMIR Backfill's storage representation for historical daily aggregates to a canonical local-noon point sample (`startDate == endDate == 12:00 local`). Noon is an indexing anchor, not an observed consumption time.

**Controlled recovery exception:** Normal imports remain append-only. A one-time destructive recovery control is added solely to remove legacy BioMIR Backfill-authored historical nutrition samples that:
- were written by the current BioMIR Backfill HealthKit source,
- carry classification `historical-user-controlled-import`,
- carry mapping version `nutrition-v0.1` or `carbmanager-total-carb-v1`,
- start within 2021-03-11 through 2025-01-08,
- have positive duration (`startDate < endDate`), and
- do not carry `co.biomir.backfill.time_anchor_policy`.

The recovery cannot delete corrected noon-point samples because corrected samples have zero duration and carry `daily-aggregate-noon-v1` metadata. Apple's HealthKit delete API also restricts deletion to objects previously saved by the calling application.

**Expected physical-device deletion count for the validated dataset:** 43,612 samples (42,217 original controlled nutrition samples + 1,395 total-carbohydrate samples). Any different count is a stop-and-investigate condition before re-import.
