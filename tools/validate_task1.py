from pathlib import Path
import plistlib
import re
import sys

root = Path(__file__).resolve().parents[1]
errors = []

required = [
    root / "BioMIRBackfill.xcodeproj" / "project.pbxproj",
    root / "BioMIRBackfill" / "App" / "BioMIRBackfillApp.swift",
    root / "BioMIRBackfill" / "App" / "ImportFlowView.swift",
    root / "BioMIRBackfill" / "Supporting" / "Info.plist",
    root / "BioMIRBackfill" / "Supporting" / "BioMIRBackfill.entitlements",
    root / "BioMIRBackfillTests" / "ArchitectureBoundaryTests.swift",
]
for p in required:
    if not p.exists():
        errors.append(f"missing required file: {p.relative_to(root)}")

info = root / "BioMIRBackfill" / "Supporting" / "Info.plist"
if info.exists():
    with info.open("rb") as f:
        data = plistlib.load(f)
    if not data.get("NSHealthShareUsageDescription"):
        errors.append("Info.plist missing NSHealthShareUsageDescription")
    if not data.get("NSHealthUpdateUsageDescription"):
        errors.append("Info.plist missing NSHealthUpdateUsageDescription")

ent = root / "BioMIRBackfill" / "Supporting" / "BioMIRBackfill.entitlements"
if ent.exists():
    with ent.open("rb") as f:
        data = plistlib.load(f)
    groups = data.get("com.apple.developer.healthkit.access", [])
    if groups:
        errors.append("Clinical Health Records must remain disabled in Task 1")
    if data.get("com.apple.developer.healthkit") is not True:
        errors.append("HealthKit entitlement missing or not true")

for swift in (root / "BioMIRBackfill").rglob("*.swift"):
    text = swift.read_text(encoding="utf-8")
    for forbidden in ("import BioMIR", "IndexEngine", "HealthKitManager", "HistoryStore.shared"):
        if forbidden in text:
            errors.append(f"forbidden BioMIR coupling in {swift.relative_to(root)}: {forbidden}")

pbx = root / "BioMIRBackfill.xcodeproj" / "project.pbxproj"
if pbx.exists():
    text = pbx.read_text(encoding="utf-8")
    for expected in (
        "PRODUCT_BUNDLE_IDENTIFIER = co.biomir.backfill;",
        "CODE_SIGN_ENTITLEMENTS = BioMIRBackfill/Supporting/BioMIRBackfill.entitlements;",
        "INFOPLIST_FILE = BioMIRBackfill/Supporting/Info.plist;",
        "BioMIRBackfillTests",
    ):
        if expected not in text:
            errors.append(f"project.pbxproj missing expected configuration: {expected}")

if errors:
    print("TASK 1 STRUCTURE: FAIL")
    for e in errors:
        print(f"- {e}")
    sys.exit(1)

print("TASK 1 STRUCTURE: PASS")
