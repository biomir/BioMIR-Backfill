# Task 4 — HealthKit Gateway Validation

**Date:** 2026-10-02  
**Status:** IMPLEMENTED; MAC/XCODE VERIFICATION REQUIRED

## Scope

Task 4 isolates all Apple Health interaction behind `HealthStoreGateway` and introduces an explicit authorization model that keeps write authorization separate from read visibility.

## Controlled safety properties

- Normal import code has no delete/replace path.
- A later change-controlled one-time recovery method, `deleteAppAuthoredSamples(matching:)`, is allowed only for the historical noon-anchor migration and is constrained by current app source, controlled classification, controlled mapping versions, historical date range, positive-duration legacy representation, and absence of the new noon-anchor metadata.
- `LiveHealthStoreGateway` otherwise uses query and save operations for normal import.
- Existing-sample queries do not mutate Apple Health.
- Write authorization uses `HKHealthStore.authorizationStatus(for:)`.
- Read visibility is never inferred from write authorization or from an empty query.
- Current Xcode 26.3 / iOS 26.2 SDK reports read visibility as `.unverifiable` because HealthKit intentionally conceals denied read access and the newer limited-history introspection API is not available in this SDK.

## Compatibility ruling

Apple's limited-history authorization introspection API is an iOS 27 API. BioMIR Backfill currently targets and is validated with Xcode 26.3 / iOS 26.2 SDK. Task 4 therefore models `.limited(...)` as a future-compatible domain state but does not reference the unavailable SDK symbol. Adoption of Xcode/iOS SDK 27 requires a controlled update to `LiveHealthStoreGateway.readVisibility(for:)`, plus new tests and change-control evidence.

## Mac validation gate

Run:

```bash
./tools/verify_task4_macos.sh
```

Required ending:

```text
TASK 4 MACOS VERIFICATION: PASS
```

## Deferred physical-device validation

Actual Health authorization prompts and Health store writes are not validated on the simulator. Physical-device authorization/write behavior remains gated to the controlled device-validation phase before any personal historical import.
