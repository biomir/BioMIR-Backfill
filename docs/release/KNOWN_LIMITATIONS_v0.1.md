# BioMIR Backfill Known Limitations v0.1

1. **Nutrition-only v1 scope.** BioMIR Backfill v1 transfers only the controlled nutrition mappings defined by `nutrition-v0.1`.
2. **Total-carbohydrate reconstruction is a separate controlled profile.** `Net Carbs (g)` is never mapped directly to HealthKit total carbohydrate. The validated `carbmanager-total-carb-v1` profile reconstructs total carbohydrate only from Net Carbs + Fiber + Sugar Alcohols + Allulose using the controlled Carb Manager source/evidence workflow.
3. **Read visibility is not proof of global absence.** HealthKit may not reveal whether read permission was denied; the app therefore states only that no conflicting records were visible to BioMIR Backfill.
4. **Normal imports are append-only.** Existing visible records win. There is no general-purpose delete, replace, or rollback operation. A one-time recovery path can delete only legacy BioMIR Backfill-authored historical nutrition samples matching the controlled 2021-03-11 through 2025-01-08 provenance/date/duration scope before noon-anchor re-import.
5. **Explicit-zero policy.** Explicit zero values are skipped under the current controlled policy and are distinguished from missing values.
6. **Daily semantics.** Historical daily aggregates use a canonical 12:00 PM local point timestamp. Noon is an indexing anchor for the source calendar date, not an observed meal or consumption time.
7. **Personal-data validation is not App Store validation.** Task 9 validates one controlled physical-device workflow only. Broader OS/device/accessibility/release compatibility remains Task 10 scope.
8. **No diagnostic or treatment function.** The app is a personal wellness-data transfer utility and does not calculate BioMIR analytical outputs, diagnose disease, recommend treatment, or interpret laboratory results.
9. **No server synchronization.** Import, provenance, audit, and verification are local; no backend or third-party analytics service is required.
10. **Source compatibility remains controlled.** Arbitrary CSV schemas and arbitrary HealthKit type mappings are outside v1 scope.
