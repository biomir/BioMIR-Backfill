# Task 8 — Guarded Historical Import Workflow Validation

Date: 2026-10-02
Baseline: validated Task 7 commit `3492d93`

## Scope

Task 8 wires the previously validated parsing, mapping, HealthKit gateway, preflight, import coordination, verification, and audit-export components into the four-stage SwiftUI workflow. It does not change nutrition semantics, HealthKit write semantics, provenance semantics, or verification criteria.

## Required workflow

1. Select Source
2. Review source/schema/mappings
3. Run and explicitly review Health preflight
4. Explicitly confirm import, then review verification/results and audit export

## Safety gates

- Source selection cannot directly invoke a HealthKit write.
- SwiftUI views contain no direct HealthKit or domain-engine calls.
- Import remains disabled until a completed preflight is explicitly acknowledged.
- The app reruns preflight immediately before import.
- Any preflight change blocks the write and requires a fresh user review.
- Unverifiable or limited Health read visibility remains visible on the preflight screen.
- If persistent local audit storage cannot initialize, import is hard-disabled.
- Post-write result status comes from Task-7 reconciliation; the UI does not infer success from the write call alone.
- Audit export is exposed only from the generated Task-7 audit bundle.

## Displayed review evidence

- source filename
- SHA-256 prefix
- row count
- source date range
- supported mapping count
- unsupported-field count and reasons
- mapping version

## Displayed preflight evidence

- eligible samples
- existing visible samples
- missing samples
- zero-policy skips
- authorization-blocked samples
- unsupported fields
- Health read-visibility warning

## Displayed result evidence

- imported count
- skip counts
- authorization-blocked count
- verified count
- verification-failure count
- Verified Complete only from exact Task-7 reconciliation
- run ID
- audit-bundle export action

## Validation commands

Run `./tools/verify_task8_macos.sh` on the controlled macOS/Xcode environment.

Expected terminal markers:

- `TASK 8 STRUCTURE: PASS`
- `TASK 8 VIEW BOUNDARY: PASS`
- `TASK 8 IMPORT GATE: PASS`
- `TASK 8 VISIBILITY GATE: PASS`
- `TASK 8 RESULT GATE: PASS`
- `TASK 8 PORTABLE WORKFLOW: PASS`
- `TASK 8 STRICT CONCURRENCY COMPILE: PASS`
- `Task 8 SwiftUI parse: PASS`
- `XCTest: PASS`
- `TASK 8 MACOS VERIFICATION: PASS`

Physical-device authorization and personal-data import remain Task 9 gates.

## Swift 6 concurrency correction

During the first macOS/Xcode Task-8 run, Swift 6 correctly rejected transfers of the main-actor-held `HealthStoreGateway` existential into nonisolated async orchestration methods. The root cause was that the gateway protocol did not express the sendability already required by the architecture.

Correction:
- `HealthStoreGateway` now conforms to `Sendable`.
- `LiveHealthStoreGateway` uses checked `Sendable` conformance; its stored `HKHealthStore` is immutable and the current Apple SDK declares `HKHealthStore` `Sendable`.
- Mutable test/portable fake gateways use test-only `@unchecked Sendable` because their state is intentionally controlled by a single test harness.
- Task-8 portable compilation now runs in Swift 6 with complete concurrency checking so this defect class fails before XCTest.

No nutrition mapping, collision policy, HealthKit write semantics, provenance, verification criteria, or audit policy changed in this correction.
