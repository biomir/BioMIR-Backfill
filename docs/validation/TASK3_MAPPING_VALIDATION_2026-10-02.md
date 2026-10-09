# Task 3 — Controlled Nutrition Mapping Validation

**Date:** 2026-10-02  
**Registry:** `nutrition-v0.1`  
**Status:** IMPLEMENTED; macOS/Xcode verification required before closure.

## Scope

Task 3 establishes the deterministic nutrition semantic mapping layer. It does not read from or write to HealthKit.

## Controlled mapping baseline

- 31 supported source fields.
- 9 explicitly unsupported source fields.
- Mapping documentation source: `docs/mapping/NUTRITION_MAPPING_v0.1.csv`.
- Runtime registry: `BioMIRBackfill/Core/Mapping/NutritionMappingRegistry.swift`.
- Machine drift check: `tools/validate_task3.py`.

## Semantic guards

- `Net Carbs (g)` is explicitly unsupported and must not map to Apple Health total carbohydrate.
- Derived `Omega 6:3 Ratio` and `Glycemic Load` remain unsupported.
- Unknown fields are reported unsupported rather than inferred.
- Missing, explicit zero, and observed numeric states are preserved through mapping.

## Controlled transformation

`Water Consumed (8oz-glass)` → dietary water uses:

`1 US 8-fl-oz glass = 236.5882365 mL`

Transformation identifier: `water-us-fl-oz-to-ml-v1`.

## Verification gates

1. Controlled mapping CSV ↔ Swift registry machine comparison.
2. Portable Swift behavior harness.
3. Xcode/XCTest suite on iOS Simulator.
4. No HealthKit persistence is introduced in Task 3.

## Current HealthKit SDK compatibility gate

`HealthKitNutritionIdentifierCompatibilityTests.swift` imports the native HealthKit framework and resolves every one of the 31 supported registry entries through an actual `HKQuantityTypeIdentifier` and `HKObjectType.quantityType(forIdentifier:)` call. This is intentionally a test-only adapter so the mapping engine remains independent of HealthKit. The Mac/Xcode Task-3 verification is not complete unless this test compiles and passes against the installed Apple SDK.
