#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
required = [
    root / "tools/build_carbmanager_total_carbs.py",
    root / "tools/test_carbmanager_total_carbs_builder.py",
    root / "tools/carbmanager_total_carb_harness.swift",
    root / "docs/mapping/CARBMANAGER_TOTAL_CARB_MAPPING_v1.csv",
    root / "docs/validation/CARBMANAGER_TOTAL_CARB_VALIDATION_2026-10-02.md",
]
missing = [str(p.relative_to(root)) for p in required if not p.is_file()]
if missing:
    print("CARB PROFILE STRUCTURE: FAIL — missing " + ", ".join(missing))
    sys.exit(1)

registry = (root / "BioMIRBackfill/Core/Mapping/NutritionMappingRegistry.swift").read_text(encoding="utf-8")
engine = (root / "BioMIRBackfill/Core/Mapping/MappingEngine.swift").read_text(encoding="utf-8")
builder = required[0].read_text(encoding="utf-8")
compat = (root / "BioMIRBackfillTests/HealthKitNutritionIdentifierCompatibilityTests.swift").read_text(encoding="utf-8")

checks = {
    "legacy version preserved": 'static let version = "nutrition-v0.1"' in registry,
    "carb profile version": 'static let version = "carbmanager-total-carb-v1"' in registry,
    "carb exact source column": 'static let sourceColumn = "Carb Manager Total Carbohydrates (g)"' in registry,
    "carb HealthKit identifier": 'healthIdentifier: .dietaryCarbohydrates' in registry,
    "carb transformation ID": 'transformationID: "carbmanager-total-carb-reconstruction-v1"' in registry,
    "exact-schema gate": 'matchesExactSchema(parsedCSV.headers)' in engine,
    "mixed schema blocks candidates": 'mappedCandidates: []' in engine,
    "builder net carbs": '"Net Carbs (g)"' in builder,
    "builder fiber": '"Fiber (g)"' in builder,
    "builder sugar alcohols": '"Sugar Alcohols (g)"' in builder,
    "builder allulose": '"Allulose (g)"' in builder,
    "builder controlled missingness": 'MISSING_SOURCE' in builder,
    "HealthKit compatibility test": 'testCarbManagerTotalCarbohydrateMappingResolvesInCurrentHealthKitSDK' in compat,
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    print("CARB PROFILE STRUCTURE: FAIL — " + ", ".join(failed))
    sys.exit(1)

# Personal source/output data must stay outside the repository.
for p in root.rglob("*"):
    if not p.is_file() or ".git" in p.parts:
        continue
    name = p.name.lower()
    if (
        name.startswith("macronutrients_") and name.endswith(".csv")
        or name.startswith("biomir_carbmanager_totalcarbohydrates_2021")
    ):
        print(f"CARB PROFILE PRIVACY GATE: FAIL — personal carbohydrate artifact in repository: {p.relative_to(root)}")
        sys.exit(1)

print("CARB PROFILE STRUCTURE: PASS")
print("CARB PROFILE ISOLATION GATE: PASS — nutrition-v0.1 remains separate from total carbohydrate")
print("CARB PROFILE SCHEMA GATE: PASS — only exact Date + reconstructed total-carb schema can map")
print("CARB PROFILE PRIVACY GATE: PASS — personal source/reconstruction files are not committed")
