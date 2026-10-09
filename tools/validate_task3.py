#!/usr/bin/env python3
from pathlib import Path
import csv, re, sys

root = Path(__file__).resolve().parents[1]
registry = root / "BioMIRBackfill/Core/Mapping/NutritionMappingRegistry.swift"
models = root / "BioMIRBackfill/Core/Mapping/MappingModels.swift"
engine = root / "BioMIRBackfill/Core/Mapping/MappingEngine.swift"
test = root / "BioMIRBackfillTests/MappingEngineTests.swift"
hk_compat_test = root / "BioMIRBackfillTests/HealthKitNutritionIdentifierCompatibilityTests.swift"
mapping_csv = root / "docs/mapping/NUTRITION_MAPPING_v0.1.csv"
pbx = root / "BioMIRBackfill.xcodeproj/project.pbxproj"

required = [registry, models, engine, test, hk_compat_test, mapping_csv, pbx]
missing = [str(p.relative_to(root)) for p in required if not p.exists()]
if missing:
    print("TASK 3 STRUCTURE: FAIL")
    print("Missing:", *missing, sep="\n - ")
    sys.exit(1)

text = registry.read_text(encoding="utf-8")
models_text = models.read_text(encoding="utf-8")
engine_text = engine.read_text(encoding="utf-8")
pbx_text = pbx.read_text(encoding="utf-8")

with mapping_csv.open(encoding="utf-8", newline="") as f:
    rows = list(csv.DictReader(f))

supported_csv = [r for r in rows if r["status"] == "SUPPORTED"]
unsupported_csv = [r for r in rows if r["status"] == "UNSUPPORTED"]
if len(supported_csv) != 31:
    print(f"TASK 3 MAPPING: FAIL — expected 31 supported CSV mappings, found {len(supported_csv)}")
    sys.exit(1)
if len(unsupported_csv) != 9:
    print(f"TASK 3 MAPPING: FAIL — expected 9 unsupported CSV mappings, found {len(unsupported_csv)}")
    sys.exit(1)

unit_by_enum = {
    "kilocalorie": "kcal",
    "gram": "g",
    "milligram": "mg",
    "microgram": "µg",
    "milliliter": "mL",
}

direct_pattern = re.compile(
    r'direct\("(?P<source>[^"]+)",\s*\.(?P<identifier>[A-Za-z0-9_]+),\s*sourceUnit:\s*"(?P<source_unit>[^"]+)",\s*healthUnit:\s*\.(?P<unit>[A-Za-z0-9_]+)\)'
)
code_supported = {}
for m in direct_pattern.finditer(text):
    code_supported[m.group("source")] = {
        "healthkit_identifier": m.group("identifier"),
        "source_unit": m.group("source_unit"),
        "health_unit": unit_by_enum[m.group("unit")],
        "multiplier": "1",
    }

water_match = re.search(
    r'sourceColumn:\s*"Water Consumed \(8oz-glass\)".*?healthIdentifier:\s*\.dietaryWater.*?sourceUnit:\s*"8 US fl oz glass".*?healthUnit:\s*\.milliliter.*?multiplier:\s*([0-9.]+).*?transformationID:\s*"water-us-fl-oz-to-ml-v1"',
    text,
    re.S,
)
if not water_match:
    print("TASK 3 MAPPING: FAIL — controlled water mapping not found")
    sys.exit(1)
code_supported["Water Consumed (8oz-glass)"] = {
    "healthkit_identifier": "dietaryWater",
    "source_unit": "8 US fl oz glass",
    "health_unit": "mL",
    "multiplier": water_match.group(1),
}

if len(code_supported) != 31:
    print(f"TASK 3 MAPPING: FAIL — Swift registry exposes {len(code_supported)} supported mappings")
    sys.exit(1)

for row in supported_csv:
    got = code_supported.get(row["source_column"])
    if got is None:
        print(f"TASK 3 MAPPING: FAIL — missing Swift mapping: {row['source_column']}")
        sys.exit(1)
    for key in ("healthkit_identifier", "source_unit", "health_unit", "multiplier"):
        expected = row[key]
        actual = got[key]
        if key == "multiplier":
            try:
                if abs(float(expected) - float(actual)) <= 1e-12:
                    continue
            except ValueError:
                pass
        if expected != actual:
            print(f"TASK 3 MAPPING: FAIL — {row['source_column']} {key}: CSV={expected!r}, Swift={actual!r}")
            sys.exit(1)

unsupported_pattern = re.compile(r'\.init\(sourceColumn:\s*"(?P<source>[^"]+)",\s*reason:\s*"(?P<reason>[^"]+)"\)')
code_unsupported = {m.group("source"): m.group("reason") for m in unsupported_pattern.finditer(text)}
if len(code_unsupported) != 9:
    print(f"TASK 3 MAPPING: FAIL — Swift registry exposes {len(code_unsupported)} unsupported mappings")
    sys.exit(1)
for row in unsupported_csv:
    if code_unsupported.get(row["source_column"]) != row["transformation"]:
        print(f"TASK 3 MAPPING: FAIL — unsupported reason drift: {row['source_column']}")
        sys.exit(1)

if "dietaryCarbohydrates" in [v["healthkit_identifier"] for v in code_supported.values()]:
    print("TASK 3 SEMANTIC GUARD: FAIL — total carbohydrate mapping must not be present in v0.1")
    sys.exit(1)
if 'case dietaryCarbohydrates' not in models_text:
    print("TASK 3 MODEL: FAIL — HealthQuantityKey must retain total-carbohydrate identity for explicit guard/testing")
    sys.exit(1)
if '"no controlled mapping in \\(NutritionMappingRegistry.version)"' not in engine_text:
    print("TASK 3 ENGINE: FAIL — unknown-column rejection reason missing")
    sys.exit(1)

for name in ["MappingModels.swift", "NutritionMappingRegistry.swift", "MappingEngine.swift", "MappingEngineTests.swift", "HealthKitNutritionIdentifierCompatibilityTests.swift"]:
    if name not in pbx_text:
        print(f"TASK 3 PROJECT: FAIL — {name} is not registered in project.pbxproj")
        sys.exit(1)

print("TASK 3 STRUCTURE: PASS")
print("TASK 3 CONTROLLED MAPPING: PASS — 31 supported / 9 unsupported")
print("TASK 3 SEMANTIC GUARD: PASS — Net Carbs is not total carbohydrate")
