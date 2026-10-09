# BioMIR Backfill HealthKit Compatibility Matrix v0.1

Status: **PARTIAL — SIMULATOR VALIDATED; PHYSICAL DEVICE PENDING TASK 9**

| Area | Environment | Status | Evidence / limitation |
|---|---|---|---|
| Swift/Xcode build | Xcode 26.3 / iPhoneSimulator 26.2 SDK | PASS through Task 8 | Full XCTest and strict Swift 6 concurrency gate passed. |
| iOS deployment target | iOS 17.0+ project target | CONFIGURED | Broader supported-version regression is Task 10. |
| HealthKit capability | Simulator project configuration | PASS | HealthKit entitlement and privacy strings present. |
| Controlled nutrition identifiers | Current SDK | PASS | 31 controlled HealthKit quantity identifiers resolve. |
| Read/write authorization | Physical iPhone | PENDING | Task 9 Gate 9A. |
| Existing-visible collision query | Physical iPhone | PENDING | Must preserve read-visibility caveat. |
| Two-row write + exact verification | Physical iPhone | PENDING | Task 9 Gate 9B. |
| Repeat-import protection | Physical iPhone | PENDING | Task 9 Gate 9B. |
| 1,400-day historical import | Physical iPhone | PENDING | Task 9 Gate 9C. |
| Limited-history behavior | Physical iPhone / supported iOS | PENDING | Explicit Task 10 release gate. |
| App Store distribution signing | Distribution build | PENDING | Task 10. |
