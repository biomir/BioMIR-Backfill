import Foundation

private final class NoonHarnessGateway: HealthStoreGateway, @unchecked Sendable {
    var isHealthDataAvailable = true
    var saved: [HealthSampleDraft] = []

    func requestAuthorization(read: Set<HealthQuantityKey>, write: Set<HealthQuantityKey>) async throws {}
    func writeAuthorizationStatus(for identifier: HealthQuantityKey) -> HealthWriteAuthorizationStatus { .sharingAuthorized }
    func readVisibility(for identifiers: Set<HealthQuantityKey>) async throws -> HealthReadVisibility { .unverifiable }
    func existingSamples(type: HealthQuantityKey, unit: ControlledUnit, start: Date, end: Date) async throws -> [HealthSampleSummary] { [] }
    func save(_ samples: [HealthSampleDraft]) async throws { saved.append(contentsOf: samples) }
    func samplesAuthoredByThisApp(externalIDs: Set<String>, unitsByType: [HealthQuantityKey : ControlledUnit]) async throws -> [HealthSampleSummary] { [] }
}

@main
struct NoonAnchorRecoveryHarness {
    static func main() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.timeZone = TimeZone(identifier: "America/New_York")!

        let repair = try HistoricalNutritionNoonRepairPolicy.deletionRequest(calendar: cal)
        precondition(repair.types == Set(HealthQuantityKey.allCases))
        precondition(repair.mappingVersions == Set(["nutrition-v0.1", "carbmanager-total-carb-v1"]))
        precondition(repair.classification == "historical-user-controlled-import")
        let repairStart = cal.dateComponents([.year,.month,.day,.hour], from: repair.startDate)
        let repairEnd = cal.dateComponents([.year,.month,.day,.hour], from: repair.endDate)
        precondition(repairStart.year == 2021 && repairStart.month == 3 && repairStart.day == 11 && repairStart.hour == 0)
        precondition(repairEnd.year == 2025 && repairEnd.month == 1 && repairEnd.day == 9 && repairEnd.hour == 0)

        let candidate = MappedCandidate(
            rowNumber: 2,
            sourceDate: DateComponents(year: 2021, month: 8, day: 22),
            sourceColumn: "Dietary Calories (kCal)",
            healthIdentifier: .dietaryEnergyConsumed,
            cellState: .value(2930),
            originalUnit: "kcal",
            healthUnit: .kilocalorie,
            normalizedValue: 2930,
            transformationID: "identity",
            transformationVersion: "1"
        )
        let mapping = MappingResult(mappedCandidates: [candidate], unsupportedFields: [], registryVersion: "nutrition-v0.1")
        let manifest = ImportManifest(
            sourceFilename: "BioMIR_HK_Nutrition_MissingOnly.csv",
            sourceSHA256: "066e6b96850f4f6709321ac92ff081b347ccf278aff4e9f335ff6151581525d2",
            sourceByteCount: 248764,
            rowCount: 1400,
            encoding: "UTF-8",
            sourceTimeZoneIdentifier: "America/New_York",
            sourceDateStart: "2021-03-11",
            sourceDateEnd: "2025-01-08",
            headers: ["Date", "Dietary Calories (kCal)"],
            schemaSHA256: String(repeating: "b", count: 64),
            parserVersion: "csv-v0.1",
            mappingVersion: "nutrition-v0.1",
            appVersion: "test",
            appBuild: "test",
            osVersion: "test",
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        let gateway = NoonHarnessGateway()
        let report = try await PreflightEngine.run(mappingResult: mapping, manifest: manifest, calendar: cal, gateway: gateway)
        precondition(report.eligible.count == 1)

        let journal = try ImportJournal(storageURL: nil)
        let ledger = try AuditLedger(storageURL: nil)
        let coordinator = ImportCoordinator(calendar: cal, journal: journal, auditLedger: ledger) { manifest.sourceSHA256 }
        let result = try await coordinator.import(report: report, gateway: gateway)
        precondition(result.importedCount == 1)
        precondition(gateway.saved.count == 1)

        let draft = gateway.saved[0]
        precondition(draft.startDate == draft.endDate)
        let anchored = cal.dateComponents([.year,.month,.day,.hour,.minute,.second], from: draft.startDate)
        precondition(anchored.year == 2021 && anchored.month == 8 && anchored.day == 22)
        precondition(anchored.hour == 12 && anchored.minute == 0 && anchored.second == 0)
        precondition(draft.value == 2930)
        precondition(draft.stringMetadata[ProvenanceService.MetadataKey.timeAnchorPolicy] == "daily-aggregate-noon-v1")

        print("NOON ANCHOR RECOVERY PORTABLE: PASS")
    }
}
