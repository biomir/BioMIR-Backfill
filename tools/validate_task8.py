#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
required = [
    root / "BioMIRBackfill/App/ImportViewModel.swift",
    root / "BioMIRBackfill/App/ImportFlowView.swift",
    root / "BioMIRBackfillTests/ImportViewModelTests.swift",
]
missing = [str(p.relative_to(root)) for p in required if not p.exists()]
if missing:
    print("TASK 8 STRUCTURE: FAIL")
    for item in missing:
        print("missing:", item)
    sys.exit(1)

view_model = required[0].read_text()
view = required[1].read_text()
tests = required[2].read_text()
pbx = (root / "BioMIRBackfill.xcodeproj/project.pbxproj").read_text()
app = (root / "BioMIRBackfill/App/BioMIRBackfillApp.swift").read_text()
gateway_protocol = (root / "BioMIRBackfill/Core/HealthKit/HealthStoreGateway.swift").read_text()
live_gateway = (root / "BioMIRBackfill/Core/HealthKit/LiveHealthStoreGateway.swift").read_text()

checks = {
    "exact four-stage state": all(token in view_model for token in ["case selectSource", "case review", "case preflight", "case results"]),
    "selection stops at review": "self.stage = .review" in view_model,
    "explicit preflight review": "preflightReviewed" in view_model and "setPreflightReviewed" in view_model,
    "import gate": "var canImport" in view_model and "preflightReviewed &&" in view_model,
    "fresh preflight before write": "let freshReport = try await buildFreshPreflight(requestAuthorization: false)" in view_model,
    "changed preflight blocks write": "guard freshReport == reviewedReport" in view_model and "ImportWorkflowError.preflightChanged" in view_model,
    "persistence hard gate": "persistentAuditAvailable &&" in view_model and "auditPersistenceUnavailable" in view_model and ".audit-write-probe-" in view_model and 'Data("BioMIR Backfill audit persistence probe".utf8).write' in view_model,
    "verification wired": "VerificationEngine(auditLedger: auditLedger)" in view_model,
    "audit export wired": "auditExporter.export" in view_model,
    "review evidence": all(token in view for token in ["SHA-256", "Supported mappings", "Unsupported fields", "Date range"]),
    "preflight evidence": all(token in view for token in ["Eligible", "Existing visible", "Zero-policy skips", "Authorization blocked"]),
    "visibility warning visible": "preflightVisibilityWarning" in view and "visibilityWarning" in view,
    "explicit confirmation": "confirmationDialog" in view and "Import to Apple Health" in view,
    "verification result visible": "Verified Complete" in view and "Verification failures" in view,
    "audit export visible": "Export Audit Bundle" in view,
    "app owns live view model": "ImportViewModel.makeLive()" in app,
    "transition tests": all(token in tests for token in ["testSourceSelectionStopsAtReviewAndCannotWrite", "testPreflightWarningRemainsVisibleAndImportRequiresExplicitReview", "testFreshPreflightChangeBlocksWriteAndRequiresReviewAgain", "testSuccessfulImportRunsVerificationAndProducesAuditBundle"]),
    "sendable gateway contract": "protocol HealthStoreGateway: Sendable" in gateway_protocol,
    "live gateway checked sendable": "final class LiveHealthStoreGateway: HealthStoreGateway, Sendable" in live_gateway,
}
for label, ok in checks.items():
    if not ok:
        print(f"TASK 8 STRUCTURE: FAIL — {label}")
        sys.exit(1)

for forbidden in ["import HealthKit", "HKHealthStore", "PreflightEngine", "ImportCoordinator", "VerificationEngine", "AuditExporter", ".save("]:
    if forbidden in view:
        print(f"TASK 8 VIEW BOUNDARY: FAIL — SwiftUI contains forbidden domain token {forbidden!r}")
        sys.exit(1)

for filename in ["ImportViewModel.swift", "ImportViewModelTests.swift"]:
    if f'path = {filename}; sourceTree = "<group>";' not in pbx:
        print(f"TASK 8 PROJECT MEMBERSHIP: FAIL — missing PBXFileReference for {filename}")
        sys.exit(1)
    if f'{filename} in Sources' not in pbx:
        print(f"TASK 8 PROJECT MEMBERSHIP: FAIL — missing Sources membership for {filename}")
        sys.exit(1)

print("TASK 8 STRUCTURE: PASS")

verify_script = (root / "tools/verify_task8_macos.sh").read_text()
portable_section = verify_script.split('echo "=== TASK 8 SWIFTUI PARSE ==="', 1)[0]
assert "BioMIRBackfill/Core/HealthKit/LiveHealthStoreGateway.swift" in portable_section, (
    "Task 8 portable compile must include LiveHealthStoreGateway.swift because makeLive() "
    "is compiled when HealthKit is available on macOS/Xcode hosts"
)
assert "-swift-version 6 -strict-concurrency=complete" in portable_section, (
    "Task 8 portable compile must enforce Swift 6 complete concurrency checking"
)
print("TASK 8 PORTABLE DEPENDENCY GATE: PASS — live HealthKit gateway included")
print("TASK 8 STRICT CONCURRENCY GATE: PASS — Swift 6 complete concurrency checking enabled")

print("TASK 8 VIEW BOUNDARY: PASS — SwiftUI dispatches view-model commands only")
print("TASK 8 IMPORT GATE: PASS — reviewed preflight + fresh pre-write preflight required")
print("TASK 8 VISIBILITY GATE: PASS — Health read-visibility warning remains surfaced")
print("TASK 8 RESULT GATE: PASS — reconciliation and audit export are visible")
