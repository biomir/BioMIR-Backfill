#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
required = [
    root / "tools/task9_prepare_validation.py",
    root / "docs/validation/TASK9_DEVICE_VALIDATION_RUNBOOK_2026-10-02.md",
    root / "docs/validation/VALIDATION_REPORT_v0.1.md",
    root / "docs/release/KNOWN_LIMITATIONS_v0.1.md",
    root / "docs/release/HEALTHKIT_COMPATIBILITY_MATRIX_v0.1.md",
]
missing = [str(p.relative_to(root)) for p in required if not p.is_file()]
if missing:
    print("TASK 9 STRUCTURE: FAIL — missing " + ", ".join(missing))
    sys.exit(1)

runbook = required[1].read_text(encoding="utf-8")
report = required[2].read_text(encoding="utf-8")
limitations = required[3].read_text(encoding="utf-8")

checks = {
    "three-gate sequence": all(x in runbook for x in ["Gate 9A", "Gate 9B", "Gate 9C"]),
    "stop before full write": "STOP. Do not perform the full historical write yet." in runbook,
    "no personal data commit": "must not be committed" in runbook,
    "repeat protection": "must not be written again" in runbook,
    "report pending": "PENDING — PHYSICAL-DEVICE EVIDENCE REQUIRED" in report,
    "no overclaim": "does not establish broader App Store compatibility" in report,
    "read visibility limitation": "not proof of global absence" in limitations,
    "append-only limitation": "no general-purpose delete, replace, or rollback" in limitations,
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    print("TASK 9 STRUCTURE: FAIL — " + ", ".join(failed))
    sys.exit(1)


# App-icon integrity gate for the physical-device build.
import json
import struct

asset_root = root / "BioMIRBackfill/Supporting/Assets.xcassets"
appicon = asset_root / "AppIcon.appiconset"
contents_path = appicon / "Contents.json"
pbxproj = root / "BioMIRBackfill.xcodeproj/project.pbxproj"

def png_ihdr(path: Path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError(f"not a PNG with IHDR: {path}")
    width, height, bit_depth, color_type = struct.unpack(">IIBB", data[16:26])
    return width, height, bit_depth, color_type

icon_expected = {
    "AppIcon-iphone-20x20-2x.png": (40, 40),
    "AppIcon-iphone-20x20-3x.png": (60, 60),
    "AppIcon-iphone-29x29-2x.png": (58, 58),
    "AppIcon-iphone-29x29-3x.png": (87, 87),
    "AppIcon-iphone-40x40-2x.png": (80, 80),
    "AppIcon-iphone-40x40-3x.png": (120, 120),
    "AppIcon-iphone-60x60-2x.png": (120, 120),
    "AppIcon-iphone-60x60-3x.png": (180, 180),
    "AppIcon-ipad-20x20-1x.png": (20, 20),
    "AppIcon-ipad-20x20-2x.png": (40, 40),
    "AppIcon-ipad-29x29-1x.png": (29, 29),
    "AppIcon-ipad-29x29-2x.png": (58, 58),
    "AppIcon-ipad-40x40-1x.png": (40, 40),
    "AppIcon-ipad-40x40-2x.png": (80, 80),
    "AppIcon-ipad-76x76-1x.png": (76, 76),
    "AppIcon-ipad-76x76-2x.png": (152, 152),
    "AppIcon-ipad-83_5x83_5-2x.png": (167, 167),
    "AppIcon-ios-marketing-1024x1024-1x.png": (1024, 1024),
}

if not contents_path.is_file():
    print("TASK 9 APP ICON GATE: FAIL — AppIcon.appiconset/Contents.json missing")
    sys.exit(1)
try:
    contents = json.loads(contents_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"TASK 9 APP ICON GATE: FAIL — invalid Contents.json: {exc}")
    sys.exit(1)
listed = {entry.get("filename") for entry in contents.get("images", []) if entry.get("filename")}
if listed != set(icon_expected):
    missing_icons = sorted(set(icon_expected) - listed)
    extra_icons = sorted(listed - set(icon_expected))
    print(f"TASK 9 APP ICON GATE: FAIL — catalog mismatch; missing={missing_icons}, extra={extra_icons}")
    sys.exit(1)
for name, expected_size in icon_expected.items():
    path = appicon / name
    if not path.is_file():
        print(f"TASK 9 APP ICON GATE: FAIL — missing {name}")
        sys.exit(1)
    try:
        width, height, bit_depth, color_type = png_ihdr(path)
    except Exception as exc:
        print(f"TASK 9 APP ICON GATE: FAIL — {name}: {exc}")
        sys.exit(1)
    if (width, height) != expected_size:
        print(f"TASK 9 APP ICON GATE: FAIL — {name} is {width}x{height}, expected {expected_size[0]}x{expected_size[1]}")
        sys.exit(1)
    if bit_depth != 8 or color_type != 2:
        print(f"TASK 9 APP ICON GATE: FAIL — {name} must be opaque 8-bit RGB; bit_depth={bit_depth}, color_type={color_type}")
        sys.exit(1)

project_text = pbxproj.read_text(encoding="utf-8")
if project_text.count("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;") < 2:
    print("TASK 9 APP ICON GATE: FAIL — AppIcon build setting missing from app configurations")
    sys.exit(1)
if "Assets.xcassets in Resources" not in project_text or "folder.assetcatalog; path = Assets.xcassets" not in project_text:
    print("TASK 9 APP ICON GATE: FAIL — Assets.xcassets is not wired into the app Resources phase")
    sys.exit(1)

# Guard against accidentally committing common personal-data exports/fixtures.
for p in root.rglob("*"):
    if not p.is_file():
        continue
    rel = p.relative_to(root).as_posix()
    lower = p.name.lower()
    if rel.startswith(".git/"):
        continue
    if lower in {"export.xml", "export.xml.zip", "biomir_backfill_master_1400d.csv", "task9_smoke_firstobserved.csv"}:
        print(f"TASK 9 PRIVACY GATE: FAIL — personal/local validation input present in repository: {rel}")
        sys.exit(1)

print("TASK 9 STRUCTURE: PASS")
print("TASK 9 PRIVACY GATE: PASS — no personal source/smoke input committed")
print("TASK 9 CLAIMS GATE: PASS — physical-device result remains explicitly pending")
print("TASK 9 APP ICON GATE: PASS — BioMIR AppIcon catalog is complete, opaque RGB, and wired into the app target")
