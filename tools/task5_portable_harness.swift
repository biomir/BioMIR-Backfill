import Foundation

private final class HarnessGateway: HealthStoreGateway, @unchecked Sendable {
    var isHealthDataAvailable = true
    var queries = 0
    var existing: [Date: [HealthSampleSummary]] = [:]
    var status: HealthWriteAuthorizationStatus = .sharingAuthorized

    func requestAuthorization(read: Set<HealthQuantityKey>, write: Set<HealthQuantityKey>) async throws {}
    func writeAuthorizationStatus(for identifier: HealthQuantityKey) -> HealthWriteAuthorizationStatus { status }
    func readVisibility(for identifiers: Set<HealthQuantityKey>) async throws -> HealthReadVisibility { .unverifiable }
    func existingSamples(type: HealthQuantityKey, unit: ControlledUnit, start: Date, end: Date) async throws -> [HealthSampleSummary] {
        queries += 1
        return existing[start] ?? []
    }
    func save(_ samples: [HealthSampleDraft]) async throws { fatalError("preflight must not save") }
    func samplesAuthoredByThisApp(externalIDs: Set<String>, unitsByType: [HealthQuantityKey : ControlledUnit]) async throws -> [HealthSampleSummary] { [] }
}

@main
struct Task5Harness {
    static func main() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let candidate = MappedCandidate(
            rowNumber: 2,
            sourceDate: DateComponents(year: 2025, month: 1, day: 1),
            sourceColumn: "Sodium (mg)",
            healthIdentifier: .dietarySodium,
            cellState: .value(1500),
            originalUnit: "mg",
            healthUnit: .milligram,
            normalizedValue: 1500,
            transformationID: "identity",
            transformationVersion: "1"
        )
        let mapping = MappingResult(mappedCandidates: [candidate], unsupportedFields: [], registryVersion: "nutrition-v0.1")
        let manifest = ImportManifest(
            sourceFilename: "history.csv",
            sourceSHA256: "abc",
            sourceByteCount: 10,
            rowCount: 1,
            encoding: "UTF-8",
            sourceTimeZoneIdentifier: "America/New_York",
            sourceDateStart: "2025-01-01",
            sourceDateEnd: "2025-01-01",
            headers: ["Date", "Sodium (mg)"],
            schemaSHA256: "schema",
            parserVersion: "csv-v0.1",
            mappingVersion: "nutrition-v0.1",
            appVersion: "0.1",
            appBuild: "5",
            osVersion: "portable",
            generatedAt: Date(timeIntervalSince1970: 1)
        )
        let gateway = HarnessGateway()
        let report = try await PreflightEngine.run(mappingResult: mapping, manifest: manifest, calendar: calendar, gateway: gateway)
        precondition(report.eligible == [candidate])
        precondition(report.count(.eligible) == 1)
        precondition(report.visibilityWarning == PreflightEngine.unverifiableVisibilityWarning)
        precondition(gateway.queries == 1)

        do {
            try SourceIntegrityGate.assertUnchanged(reviewedManifest: manifest, currentSHA256: "changed")
            fatalError("source hash mismatch must throw")
        } catch SourceIntegrityError.sourceChanged(let reviewed, let current) {
            precondition(reviewed == "abc")
            precondition(current == "changed")
        }

        print("TASK 5 PORTABLE PREFLIGHT: PASS")
    }
}
