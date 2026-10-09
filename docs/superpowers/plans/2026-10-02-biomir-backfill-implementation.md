# BioMIR Backfill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an App-Store-ready, local-only iOS companion that safely imports supported historical nutrition data into Apple Health with visible-collision preflight, deterministic provenance, resumable batches, post-write verification, and audit export.

**Architecture:** A SwiftUI shell depends on small deterministic services behind protocols. Pure parsing/mapping/audit logic is tested without HealthKit; all Apple Health interaction is isolated behind `HealthStoreGateway`. BioMIR is not linked or modified.

**Tech Stack:** Swift 6 language mode where supported by installed Xcode; SwiftUI; Foundation; HealthKit; CryptoKit; XCTest; native Apple frameworks only for v1.

**Spec:** `docs/superpowers/specs/2026-10-02-biomir-backfill-design.md`

## Global Constraints

- Product is a standalone app named `BioMIR Backfill`; BioMIR remains read-only and unchanged.
- Initial release scope is nutrition-only.
- No HealthKit delete or replace functionality may exist in production code.
- Existing visible Apple Health data always wins.
- Missing, zero, and observed values remain distinct.
- Unsupported semantic mappings are rejected, not inferred.
- Source bytes are SHA-256 fingerprinted before processing.
- Every mapping/transformation is versioned and auditable.
- No account, backend, ad SDK, analytics SDK, third-party health processor, generative AI, or iCloud health-data storage.
- No BioMIR analytical engine may be linked into this target.
- Daily aggregates use calendar-day intervals derived with `Calendar`, never fixed 86,400-second arithmetic.
- Clinical Health Records capability remains disabled.
- App Store bundle identifier baseline: `co.biomir.backfill` (verify account availability before distribution).
- Personal-device validation precedes bulk historical import.

## Review Focus

1. **Read authorization denied but write granted:** preflight must not claim a day/type is duplicate-free; UI must surface visibility limitation.
2. **DST/timezone transition days:** calendar-day intervals must preserve the intended local source date without 23/25-hour day errors.
3. **Explicit zero vs missing:** parser/audit must retain the distinction; mapping/write policy must not silently invent data.
4. **Interrupted batch:** reopening must never delete successful writes and must resume only after re-preflight/reconciliation.
5. **Source changed after preflight:** import must block when current source SHA-256 differs from the reviewed manifest.

---

## Planned file structure

```text
BioMIRBackfill/
  App/
    BioMIRBackfillApp.swift
    ImportFlowView.swift
    ImportViewModel.swift
  Core/
    CSV/
      SourceDocumentService.swift
      CSVParser.swift
      CSVModels.swift
    Mapping/
      NutritionMappingRegistry.swift
      MappingEngine.swift
      MappingModels.swift
    HealthKit/
      HealthStoreGateway.swift
      LiveHealthStoreGateway.swift
      HealthAuthorizationState.swift
    Import/
      PreflightEngine.swift
      ImportCoordinator.swift
      ImportModels.swift
      ImportJournal.swift
    Audit/
      SourceFingerprint.swift
      ImportManifest.swift
      AuditLedger.swift
      AuditExporter.swift
      ProvenanceService.swift
    Verification/
      VerificationEngine.swift
      VerificationModels.swift

BioMIRBackfillTests/
  CSVParserTests.swift
  MappingEngineTests.swift
  SourceFingerprintTests.swift
  PreflightEngineTests.swift
  ImportCoordinatorTests.swift
  AuditLedgerTests.swift
  VerificationEngineTests.swift
  CalendarIntervalTests.swift
  Fixtures/
```

### Task 1: Create the standalone iOS target and immutable project boundaries

**Files:**
- Create Xcode project: `BioMIRBackfill.xcodeproj`
- Create: `BioMIRBackfill/App/BioMIRBackfillApp.swift`
- Create: `BioMIRBackfill/App/ImportFlowView.swift`
- Create: `BioMIRBackfillTests/ArchitectureBoundaryTests.swift`
- Modify project settings: HealthKit capability and privacy usage descriptions

**Interfaces:**
- Consumes: approved design spec.
- Produces: compiling standalone app target and test target; no BioMIR dependency.

- [ ] **Step 1: Write the failing architecture-boundary test**
  Assert the app module can be imported by tests and contains no link/import to BioMIR analytical modules.

- [ ] **Step 2: Run the test**
  Run: `xcodebuild test -project BioMIRBackfill.xcodeproj -scheme BioMIRBackfill -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
  Expected: FAIL because the project/target does not yet exist.

- [ ] **Step 3: Create the Xcode project and target**
  Configure product name `BioMIR Backfill`, baseline bundle identifier `co.biomir.backfill`, SwiftUI lifecycle, HealthKit capability, and both Health usage descriptions. Do not enable Clinical Health Records.

- [ ] **Step 4: Add a minimal four-stage navigation shell**
  Stages: `Select Source`, `Review`, `Preflight`, `Results`. No Health write action yet.

- [ ] **Step 5: Run build/tests**
  Expected: app and test target compile; architecture-boundary test passes.

- [ ] **Step 6: Commit**
  `git commit -m "chore: scaffold standalone BioMIR Backfill app"`

---

### Task 2: Implement source intake, fingerprinting, and deterministic CSV parsing

**Files:**
- Create: `BioMIRBackfill/Core/CSV/SourceDocumentService.swift`
- Create: `BioMIRBackfill/Core/CSV/CSVModels.swift`
- Create: `BioMIRBackfill/Core/CSV/CSVParser.swift`
- Create: `BioMIRBackfill/Core/Audit/SourceFingerprint.swift`
- Test: `BioMIRBackfillTests/CSVParserTests.swift`
- Test: `BioMIRBackfillTests/SourceFingerprintTests.swift`
- Test: `BioMIRBackfillTests/CalendarIntervalTests.swift`

**Interfaces:**
- Produces:
  - `SourceFingerprint.sha256(url:) throws -> String`
  - `CSVParser.parse(data: Data, sourceTimeZone: TimeZone) throws -> ParsedCSV`
  - `ParsedCSV.headers: [String]`
  - `ParsedCSV.rows: [CSVRow]`
  - `CSVRow.sourceDate: DateComponents`
  - `CSVCellState = .missing | .explicitZero | .value(Double)`

- [ ] **Step 1: Add fixture tests**
  Include valid quoted CSV, malformed quoting, UTF-8 BOM, blank cell, explicit zero, nonfinite value, ISO date, and duplicate date fixtures.

- [ ] **Step 2: Run targeted tests**
  Expected: FAIL because parser/fingerprint types are undefined.

- [ ] **Step 3: Implement SHA-256 fingerprinting**
  Use CryptoKit only; return lowercase hex digest of original bytes.

- [ ] **Step 4: Implement CSV parser**
  Preserve cell state; require canonical `Date`; reject malformed/duplicate-date rows rather than silently repairing.

- [ ] **Step 5: Implement calendar-day interval helper**
  Signature: `dayInterval(for: DateComponents, calendar: Calendar) throws -> DateInterval`.
  Test DST spring/fall transition dates in `America/New_York`.

- [ ] **Step 6: Run tests**
  Expected: all Task 2 tests PASS.

- [ ] **Step 7: Commit**
  `git commit -m "feat: add deterministic source parsing and fingerprinting"`

---

### Task 3: Implement the controlled nutrition mapping registry and transformation engine

**Files:**
- Create: `BioMIRBackfill/Core/Mapping/MappingModels.swift`
- Create: `BioMIRBackfill/Core/Mapping/NutritionMappingRegistry.swift`
- Create: `BioMIRBackfill/Core/Mapping/MappingEngine.swift`
- Test: `BioMIRBackfillTests/MappingEngineTests.swift`
- Source-of-truth documentation: `docs/mapping/NUTRITION_MAPPING_v0.1.csv`

**Interfaces:**
- Produces:
  - `MappingRegistry.version == "nutrition-v0.1"`
  - `MappingEngine.map(parsedCSV:) -> MappingResult`
  - `MappedCandidate` carrying original field/value/unit, normalized value/unit, Health identifier, source date, transformation ID/version.
  - `UnsupportedField` with explicit reason.

- [ ] **Step 1: Write mapping-registry tests**
  Assert all 31 supported historical columns map to the intended Health identifiers/units and all listed unsupported fields remain unsupported.

- [ ] **Step 2: Write semantic-guard tests**
  Assert `Net Carbs (g)` never maps to total carbohydrate. Assert derived ratios never map.

- [ ] **Step 3: Write water-conversion test**
  `1 × 8 US fl oz glass` must normalize to `236.5882365 mL` under transformation ID `water-us-fl-oz-to-ml-v1`.

- [ ] **Step 4: Implement immutable mapping definitions**
  Code values must match the controlled mapping CSV exactly.

- [ ] **Step 5: Implement MappingEngine**
  No inference outside registry aliases. Preserve `.missing` and `.explicitZero`.

- [ ] **Step 6: Run tests**
  Expected: PASS with exact 31 supported mapping definitions.

- [ ] **Step 7: Commit**
  `git commit -m "feat: add controlled nutrition mapping engine"`

---

### Task 4: Isolate HealthKit behind a gateway and implement authorization/visibility semantics

**Files:**
- Create: `BioMIRBackfill/Core/HealthKit/HealthStoreGateway.swift`
- Create: `BioMIRBackfill/Core/HealthKit/LiveHealthStoreGateway.swift`
- Create: `BioMIRBackfill/Core/HealthKit/HealthAuthorizationState.swift`
- Test: `BioMIRBackfillTests/PreflightEngineTests.swift` using a fake gateway

**Interfaces:**
- Produces protocol:
  - `requestAuthorization(read:write:) async throws`
  - `writeAuthorizationStatus(for:) -> HKAuthorizationStatus`
  - `existingSamples(type:start:end:) async throws -> [HealthSampleSummary]`
  - `save(_ samples: [HKObject]) async throws`
  - `samplesAuthoredByThisApp(externalIDs:) async throws -> [HealthSampleSummary]`
- No delete method exists in the protocol.

- [ ] **Step 1: Write compile-time gateway tests**
  Fake gateway supports query/save only; production protocol contains no delete/replace API.

- [ ] **Step 2: Implement authorization state model**
  Model write status separately from read visibility and include `.readVisibilityUnverifiable`.

- [ ] **Step 3: Implement LiveHealthStoreGateway**
  Use HealthKit native APIs only. Convert callbacks to async safely.

- [ ] **Step 4: Add physical-device integration checklist**
  Document expected authorization prompts and limited-history behavior in validation evidence.

- [ ] **Step 5: Run unit tests and simulator build**
  HealthKit integration code must compile without requiring a successful simulator authorization flow.

- [ ] **Step 6: Commit**
  `git commit -m "feat: isolate HealthKit authorization and persistence gateway"`

---

### Task 5: Implement preflight classification and source-change gate

**Files:**
- Create: `BioMIRBackfill/Core/Import/ImportModels.swift`
- Create: `BioMIRBackfill/Core/Import/PreflightEngine.swift`
- Create: `BioMIRBackfill/Core/Audit/ImportManifest.swift`
- Test: `BioMIRBackfillTests/PreflightEngineTests.swift`

**Interfaces:**
- Produces:
  - `PreflightEngine.run(source:mappings:gateway:) async throws -> PreflightReport`
  - `CandidateDisposition`
  - `PreflightReport.manifest`
  - `PreflightReport.eligible`
  - `PreflightReport.dispositions`
  - `PreflightReport.visibilityWarning`

- [ ] **Step 1: Write collision tests**
  Visible existing sample → `SKIPPED_EXISTING`; absent sample → `ELIGIBLE`.

- [ ] **Step 2: Write read-visibility limitation test**
  Fake gateway with unverifiable read visibility must set warning and must not label report universally duplicate-free.

- [ ] **Step 3: Write source-change test**
  Recompute SHA-256 immediately before import; mismatch from reviewed manifest must block import.

- [ ] **Step 4: Implement manifest creation**
  Include source hash, schema hash, date range, parser version, mapping version, source timezone, app/build/iOS placeholders supplied by environment.

- [ ] **Step 5: Implement PreflightEngine**
  Query by controlled calendar intervals and mapping type. Existing visible data wins.

- [ ] **Step 6: Run tests**
  Expected: all preflight tests PASS.

- [ ] **Step 7: Commit**
  `git commit -m "feat: add collision-safe import preflight"`

---

### Task 6: Implement provenance, audit ledger, batching, and resumable import

**Files:**
- Create: `BioMIRBackfill/Core/Audit/ProvenanceService.swift`
- Create: `BioMIRBackfill/Core/Audit/AuditLedger.swift`
- Create: `BioMIRBackfill/Core/Import/ImportJournal.swift`
- Create: `BioMIRBackfill/Core/Import/ImportCoordinator.swift`
- Test: `BioMIRBackfillTests/ImportCoordinatorTests.swift`
- Test: `BioMIRBackfillTests/AuditLedgerTests.swift`

**Interfaces:**
- Produces:
  - `ProvenanceService.metadata(for:) -> [String: Any]`
  - deterministic `externalUUID`/external identity
  - `AuditLedger.append(_:)`
  - `ImportCoordinator.import(report:batchSize:gateway:) async -> ImportResult`
  - batch size default `200`, allowed `100...250`
  - forward-only `ImportJournal`

- [ ] **Step 1: Write deterministic identity test**
  Same source hash + row + Health type + date + mapping version → same identity; any controlled input change → different identity.

- [ ] **Step 2: Write audit disposition tests**
  Every candidate ends in exactly one allowed disposition; audit summary totals reconcile.

- [ ] **Step 3: Write interrupted-batch test**
  Fake gateway succeeds for first batch and throws on second; journal persists first-batch completion.

- [ ] **Step 4: Write resume test**
  New run preflights again and schedules only still-missing records; no deletion path exists.

- [ ] **Step 5: Implement provenance and ledger**
  Persist only local controlled metadata; hash exported audit artifacts.

- [ ] **Step 6: Implement ImportCoordinator**
  Re-check source hash; re-check write authorization; construct Health samples; save bounded batches; journal outcomes.

- [ ] **Step 7: Run tests**
  Expected: batching, failure, resume, and audit tests PASS.

- [ ] **Step 8: Commit**
  `git commit -m "feat: add provenance and resumable append-only import"`

---

### Task 7: Implement post-write verification and audit export

**Files:**
- Create: `BioMIRBackfill/Core/Verification/VerificationModels.swift`
- Create: `BioMIRBackfill/Core/Verification/VerificationEngine.swift`
- Create: `BioMIRBackfill/Core/Audit/AuditExporter.swift`
- Test: `BioMIRBackfillTests/VerificationEngineTests.swift`

**Interfaces:**
- Produces:
  - `VerificationEngine.verify(importResult:gateway:) async -> VerificationReport`
  - `AuditExporter.export(manifest:ledger:verification:) throws -> URL`

- [ ] **Step 1: Write verification-match tests**
  Exact type/value/unit/date/external identity/provenance match → verified.

- [ ] **Step 2: Write mismatch tests**
  Missing sample, wrong value, wrong date interval, or missing external identity → `VERIFICATION_FAILED`.

- [ ] **Step 3: Implement VerificationEngine**
  Query only app-authored external identities from the completed batch.

- [ ] **Step 4: Implement AuditExporter**
  Export manifest, controlled mapping version, ledger, verification summary, and SHA-256 hashes in a local bundle.

- [ ] **Step 5: Run tests**
  Expected: PASS; `Verified Complete` available only when reconciliation is exact.

- [ ] **Step 6: Commit**
  `git commit -m "feat: add post-write verification and audit export"`

---

### Task 8: Wire the four-stage SwiftUI flow without embedding domain logic in views

**Files:**
- Create: `BioMIRBackfill/App/ImportViewModel.swift`
- Modify: `BioMIRBackfill/App/ImportFlowView.swift`
- Test: add view-model tests under `BioMIRBackfillTests/ImportViewModelTests.swift`

**Interfaces:**
- Consumes all prior engines.
- Produces user flow:
  1. Choose CSV
  2. Review schema/mappings
  3. Review Health preflight
  4. Explicitly import and view verified result

- [ ] **Step 1: Write view-model state-transition tests**
  No path from source selection directly to write; import action disabled until successful reviewed preflight.

- [ ] **Step 2: Write visibility-warning UI-state test**
  Unverifiable Health read visibility must remain visible on the preflight screen.

- [ ] **Step 3: Implement ImportViewModel**
  Views call view-model commands only; no direct HealthKit API usage in SwiftUI files.

- [ ] **Step 4: Implement minimal publication-grade screens**
  Avoid analytics/dashboard scope. Include mapping counts, source fingerprint prefix, date range, eligible/existing/rejected counts, explicit import confirmation, result reconciliation, and audit export.

- [ ] **Step 5: Run tests/build**
  Expected: state tests PASS and app builds.

- [ ] **Step 6: Commit**
  `git commit -m "feat: add guarded historical import workflow"`

---

### Task 9: Execute controlled device validation on the personal 1,400-day nutrition dataset

**Files:**
- Add controlled source under local test inputs only; do not commit personal health data.
- Create validation result: `docs/validation/VALIDATION_REPORT_v0.1.md`
- Create: `docs/release/KNOWN_LIMITATIONS_v0.1.md`
- Create/update compatibility matrix under `docs/release/`

**Interfaces:**
- Consumes built app, approved mapping, personal source file, physical iPhone.
- Produces validation evidence only after successful dry run and import.

- [ ] **Step 1: Run pure test suite**
  `xcodebuild test ...`
  Expected: PASS.

- [ ] **Step 2: Install on physical iPhone**
  Use Personal Team signing for private validation.

- [ ] **Step 3: Perform authorization validation**
  Grant intended nutrition read/write access; document device/iOS/app build.

- [ ] **Step 4: Run dry preflight on the 1,400-day source**
  Record source SHA-256, 2021-03-11 through 2025-01-08 date range, mapping counts, existing visible samples, eligible samples, rejects, and visibility warning state.
  **STOP:** review before write.

- [ ] **Step 5: Execute controlled import**
  Import in bounded batches. Capture any deviations.

- [ ] **Step 6: Run final verification**
  Require exact reconciliation before `Verified Complete`.

- [ ] **Step 7: Re-run preflight**
  Application-authored imported records must now classify as existing/skipped rather than eligible.

- [ ] **Step 8: Export audit bundle**
  Verify bundle hashes and summary reconciliation.

- [ ] **Step 9: Write validation report**
  Do not claim broader App Store validation from one personal-device run.

- [ ] **Step 10: Commit documentation only**
  Never commit personal CSV/XML/Health exports.
  `git commit -m "docs: record BioMIR Backfill personal validation"`

---

### Task 10: App Store hardening and release gate

**Files:**
- Create/update privacy policy source under `docs/release/`
- Create HealthKit compatibility matrix
- Create requirements traceability matrix
- Create risk register
- Create SBOM/dependency inventory
- Create change log and release manifest

**Interfaces:**
- Produces public-release evidence and metadata; no new data-family scope.

- [ ] **Step 1: Run clean-install and current-iOS regression**
  Validate current supported iOS versions and physical-device behavior.

- [ ] **Step 2: Validate limited-history authorization behavior**
  Confirm UI never overstates duplicate detection.

- [ ] **Step 3: Complete risk/traceability review**
  Every high/medium identified risk has a control and test reference.

- [ ] **Step 4: Review privacy and App Store metadata**
  Confirm no health advertising/data-mining use and intended-use wording remains transfer-only.

- [ ] **Step 5: Review regulatory boundary**
  Confirm release claims did not drift into diagnosis/treatment/clinical decision support.

- [ ] **Step 6: Tag controlled release**
  Preserve source tag, build ID, mapping/schema versions, validation report, compatibility matrix, SBOM, and release manifest.

- [ ] **Step 7: Commit**
  `git commit -m "release: prepare BioMIR Backfill v1.0 evidence set"`

---

## Self-review results

- **Spec coverage:** All approved design sections map to Tasks 1–10.
- **Critical safety coverage:** no-delete boundary, read-visibility limitation, source hash gate, DST dates, missing-vs-zero, interruption/resume, and post-write reconciliation all have explicit tests.
- **Type/interface consistency:** parsing → mapping → gateway → preflight → import → verification interfaces are one-directional; UI depends on engines, engines do not depend on UI.
- **Scope control:** no arbitrary HealthKit import, BioMIR analytics, clinical record writing, backend, or AI work is included.
- **Validation boundary:** personal-device validation is separated from App Store release validation.
