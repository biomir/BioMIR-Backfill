# Task 1 Scaffold Validation — 2026-10-02

## Scope

Task 1 establishes the standalone `BioMIRBackfill.xcodeproj`, HealthKit capability configuration, Health privacy usage descriptions, the initial four-stage SwiftUI navigation shell, and architecture-boundary XCTest coverage.

No Apple Health read/write behavior is implemented in Task 1.

## TDD evidence

### RED

`python3 tools/validate_task1.py` failed before production scaffold creation with the expected missing artifacts:

- `BioMIRBackfill.xcodeproj/project.pbxproj`
- `BioMIRBackfill/App/BioMIRBackfillApp.swift`
- `BioMIRBackfill/App/ImportFlowView.swift`
- `BioMIRBackfill/Supporting/Info.plist`
- `BioMIRBackfill/Supporting/BioMIRBackfill.entitlements`

### GREEN — portable checks

The following pass in the implementation environment:

- `python3 tools/validate_task1.py`
- `plutil -lint BioMIRBackfill/Supporting/Info.plist`
- `plutil -lint BioMIRBackfill/Supporting/BioMIRBackfill.entitlements`
- `plutil -lint BioMIRBackfill.xcodeproj/project.pbxproj`
- XML parse of the shared Xcode scheme
- Swift frontend syntax parsing of both application Swift files and `ArchitectureBoundaryTests.swift`
- `git diff --check`

## Architecture invariants checked

- Bundle identifier baseline: `co.biomir.backfill`
- HealthKit entitlement enabled
- Clinical Health Records entitlement absent
- `NSHealthShareUsageDescription` present
- `NSHealthUpdateUsageDescription` present
- Unit-test target present
- No `import BioMIR`
- No `IndexEngine`
- No `HealthKitManager`
- No `HistoryStore.shared`
- Initial stages remain exactly: Select Source → Review → Preflight → Results

## Pending platform gate

The implementation environment is Linux and cannot execute `xcodebuild`, SwiftUI, HealthKit, or iOS XCTest linking. Therefore Task 1 is not considered platform-validated until the following succeeds on macOS with Xcode:

```bash
cd /Users/biomir/Desktop/BioMIR_Backfill
./tools/verify_task1_macos.sh
```

The script performs:

1. structural validation;
2. plist/project validation;
3. iOS Simulator app build;
4. automatic selection/boot of an available iPhone simulator;
5. XCTest execution.

Task 2 must not begin if this macOS gate fails.
