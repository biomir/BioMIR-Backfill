from pathlib import Path

root = Path(__file__).resolve().parents[1]
csvmodels = (root / "BioMIRBackfill/Core/CSV/CSVModels.swift").read_text()
coordinator = (root / "BioMIRBackfill/Core/Import/ImportCoordinator.swift").read_text()
prov = (root / "BioMIRBackfill/Core/Audit/ProvenanceService.swift").read_text()
gateway = (root / "BioMIRBackfill/Core/HealthKit/LiveHealthStoreGateway.swift").read_text()
protocol = (root / "BioMIRBackfill/Core/HealthKit/HealthStoreGateway.swift").read_text()
viewmodel = (root / "BioMIRBackfill/App/ImportViewModel.swift").read_text()
view = (root / "BioMIRBackfill/App/ImportFlowView.swift").read_text()

checks = {
    "noon helper exists": "static func noonAnchor(" in csvmodels,
    "import uses noon helper": "CalendarDayInterval.noonAnchor" in coordinator,
    "point sample start=end": "startDate: anchor" in coordinator and "endDate: anchor" in coordinator,
    "anchor metadata key": 'timeAnchorPolicy = "co.biomir.backfill.time_anchor_policy"' in prov,
    "anchor metadata value": '"daily-aggregate-noon-v1"' in prov,
    "repair exact mapping versions": '"nutrition-v0.1"' in protocol and '"carbmanager-total-carb-v1"' in protocol,
    "repair all controlled nutrition types": "Set(HealthQuantityKey.allCases)" in protocol,
    "repair exact historical start": "year: 2021, month: 3, day: 11" in protocol,
    "repair exact historical end": "year: 2025, month: 1, day: 8" in protocol,
    "live recovery requires old positive duration": "sample.startDate < sample.endDate" in gateway,
    "live recovery excludes new anchor metadata": "anchorPolicy == nil" in gateway,
    "live recovery source constrained": "HKSource.default()" in gateway,
    "live recovery mapping metadata constrained": "MetadataKey.mappingVersion" in gateway,
    "live recovery classification constrained": "MetadataKey.classification" in gateway,
    "recovery confirmation present": "Remove Legacy Backfill Samples" in view,
    "recovery expected count": "43_612" in viewmodel,
    "delete wrapper explicitly types Void continuation": "CheckedContinuation<Void, Error>" in gateway,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'} — {name}")
if failed:
    raise SystemExit("NOON RECOVERY VALIDATION FAILED: " + ", ".join(failed))

print("NOON ANCHOR RECOVERY STRUCTURE: PASS")
