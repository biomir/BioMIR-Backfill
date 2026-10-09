import Foundation
import XCTest
@testable import BioMIRBackfill

final class PreflightEngineTests: XCTestCase {
    func testVisibleExistingSampleWinsAndAbsentSlotIsEligible() async throws {
        let first = candidate(day: 1, type: .dietarySodium, value: 1500, unit: .milligram)
        let second = candidate(day: 2, type: .dietarySodium, value: 1600, unit: .milligram)
        let existing = HealthSampleSummary(
            uuid: UUID(),
            typeIdentifier: .dietarySodium,
            value: 1400,
            unit: .milligram,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 1, 2),
            sourceBundleIdentifier: "com.example.other",
            externalID: nil, wasUserEntered: nil, stringMetadata: [:]
        )
        let gateway = PreflightFakeGateway(
            writeStatuses: [.dietarySodium: .sharingAuthorized],
            existingByStart: [date(2025, 1, 1): [existing]]
        )

        let report = try await PreflightEngine.run(
            mappingResult: result([first, second]),
            manifest: manifest(),
            calendar: calendar(),
            gateway: gateway
        )

        XCTAssertEqual(report.count(.skippedExisting), 1)
        XCTAssertEqual(report.count(.eligible), 1)
        XCTAssertEqual(report.eligible, [second])
        XCTAssertEqual(gateway.queryCount, 2)
    }

    func testUnverifiableReadVisibilityProducesWarningWithoutClaimingFullAccess() async throws {
        let gateway = PreflightFakeGateway(
            writeStatuses: [.dietarySodium: .sharingAuthorized],
            readVisibilityValue: .unverifiable
        )

        let report = try await PreflightEngine.run(
            mappingResult: result([candidate(day: 1, type: .dietarySodium, value: 1500, unit: .milligram)]),
            manifest: manifest(),
            calendar: calendar(),
            gateway: gateway
        )

        XCTAssertEqual(report.readVisibility, .unverifiable)
        XCTAssertEqual(report.visibilityWarning, PreflightEngine.unverifiableVisibilityWarning)
    }

    func testMissingAndExplicitZeroAreClassifiedWithoutHealthQueries() async throws {
        let missing = candidate(day: 1, type: .dietarySodium, state: .missing, unit: .milligram)
        let zero = candidate(day: 2, type: .dietarySodium, state: .explicitZero, unit: .milligram)
        let gateway = PreflightFakeGateway(writeStatuses: [.dietarySodium: .sharingAuthorized])

        let report = try await PreflightEngine.run(
            mappingResult: result([missing, zero]),
            manifest: manifest(),
            calendar: calendar(),
            gateway: gateway
        )

        XCTAssertEqual(report.count(.skippedMissing), 1)
        XCTAssertEqual(report.count(.skippedZeroPolicy), 1)
        XCTAssertEqual(gateway.queryCount, 0)
    }

    func testUnauthorizedWriteIsBlockedWithoutHealthQuery() async throws {
        let gateway = PreflightFakeGateway(writeStatuses: [.dietarySodium: .sharingDenied])

        let report = try await PreflightEngine.run(
            mappingResult: result([candidate(day: 1, type: .dietarySodium, value: 1500, unit: .milligram)]),
            manifest: manifest(),
            calendar: calendar(),
            gateway: gateway
        )

        XCTAssertEqual(report.count(.authorizationBlocked), 1)
        XCTAssertEqual(report.eligible.count, 0)
        XCTAssertEqual(gateway.queryCount, 0)
    }

    func testSourceHashMismatchHardFailsBeforeImport() throws {
        XCTAssertThrowsError(
            try SourceIntegrityGate.assertUnchanged(
                reviewedManifest: manifest(sourceSHA256: "reviewed"),
                currentSHA256: "changed"
            )
        ) { error in
            XCTAssertEqual(
                error as? SourceIntegrityError,
                .sourceChanged(reviewedSHA256: "reviewed", currentSHA256: "changed")
            )
        }
    }

    func testManifestFactoryCapturesSourceSchemaAndVersionProvenance() throws {
        let data = Data("Date,Sodium (mg)\n2025-01-01,1500\n".utf8)
        let source = LoadedSourceDocument(
            url: URL(fileURLWithPath: "/tmp/history.csv"),
            filename: "history.csv",
            data: data,
            sha256: SourceFingerprint.sha256(data: data)
        )
        let parsed = ParsedCSV(
            headers: ["Date", "Sodium (mg)"],
            rows: [CSVRow(rowNumber: 2, sourceDate: components(2025, 1, 1), cells: ["Sodium (mg)": .value(1500)])],
            sourceTimeZoneIdentifier: "America/New_York",
            encoding: "UTF-8"
        )
        let mapping = result([candidate(day: 1, type: .dietarySodium, value: 1500, unit: .milligram)])
        let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let built = ImportManifestFactory.make(
            source: source,
            parsedCSV: parsed,
            mappingResult: mapping,
            environment: ImportManifestEnvironment(
                appVersion: "0.1",
                appBuild: "5",
                osVersion: "iOS 26.2",
                generatedAt: generatedAt
            )
        )

        XCTAssertEqual(built.sourceFilename, "history.csv")
        XCTAssertEqual(built.sourceSHA256, source.sha256)
        XCTAssertEqual(built.sourceByteCount, data.count)
        XCTAssertEqual(built.rowCount, 1)
        XCTAssertEqual(built.sourceDateStart, "2025-01-01")
        XCTAssertEqual(built.sourceDateEnd, "2025-01-01")
        XCTAssertEqual(built.parserVersion, CSVParser.version)
        XCTAssertEqual(built.mappingVersion, NutritionMappingRegistry.version)
        XCTAssertFalse(built.schemaSHA256.isEmpty)
        XCTAssertEqual(built.generatedAt, generatedAt)
    }

    private func candidate(
        day: Int,
        type: HealthQuantityKey,
        value: Double,
        unit: ControlledUnit
    ) -> MappedCandidate {
        candidate(day: day, type: type, state: .value(value), unit: unit)
    }

    private func candidate(
        day: Int,
        type: HealthQuantityKey,
        state: CSVCellState,
        unit: ControlledUnit
    ) -> MappedCandidate {
        MappedCandidate(
            rowNumber: day + 1,
            sourceDate: components(2025, 1, day),
            sourceColumn: "Sodium (mg)",
            healthIdentifier: type,
            cellState: state,
            originalUnit: "mg",
            healthUnit: unit,
            normalizedValue: {
                switch state {
                case .missing: nil
                case .explicitZero: 0
                case .value(let value): value
                }
            }(),
            transformationID: "identity",
            transformationVersion: "1"
        )
    }

    private func result(_ candidates: [MappedCandidate]) -> MappingResult {
        MappingResult(
            mappedCandidates: candidates,
            unsupportedFields: [UnsupportedField(sourceColumn: "Net Carbs (g)", reason: "semantic mismatch")],
            registryVersion: NutritionMappingRegistry.version
        )
    }

    private func manifest(sourceSHA256: String = "abc123") -> ImportManifest {
        ImportManifest(
            sourceFilename: "history.csv",
            sourceSHA256: sourceSHA256,
            sourceByteCount: 100,
            rowCount: 2,
            encoding: "UTF-8",
            sourceTimeZoneIdentifier: "America/New_York",
            sourceDateStart: "2025-01-01",
            sourceDateEnd: "2025-01-02",
            headers: ["Date", "Sodium (mg)"],
            schemaSHA256: "schema",
            parserVersion: CSVParser.version,
            mappingVersion: NutritionMappingRegistry.version,
            appVersion: "0.1",
            appBuild: "5",
            osVersion: "iOS 26.2",
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func components(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day))!
    }
}

private final class PreflightFakeGateway: HealthStoreGateway, @unchecked Sendable {
    var isHealthDataAvailable = true
    var writeStatuses: [HealthQuantityKey: HealthWriteAuthorizationStatus]
    var readVisibilityValue: HealthReadVisibility
    var existingByStart: [Date: [HealthSampleSummary]]
    var queryCount = 0

    init(
        writeStatuses: [HealthQuantityKey: HealthWriteAuthorizationStatus] = [:],
        readVisibilityValue: HealthReadVisibility = .unverifiable,
        existingByStart: [Date: [HealthSampleSummary]] = [:]
    ) {
        self.writeStatuses = writeStatuses
        self.readVisibilityValue = readVisibilityValue
        self.existingByStart = existingByStart
    }

    func requestAuthorization(read: Set<HealthQuantityKey>, write: Set<HealthQuantityKey>) async throws {}

    func writeAuthorizationStatus(for identifier: HealthQuantityKey) -> HealthWriteAuthorizationStatus {
        writeStatuses[identifier] ?? .notDetermined
    }

    func readVisibility(for identifiers: Set<HealthQuantityKey>) async throws -> HealthReadVisibility {
        readVisibilityValue
    }

    func existingSamples(
        type: HealthQuantityKey,
        unit: ControlledUnit,
        start: Date,
        end: Date
    ) async throws -> [HealthSampleSummary] {
        queryCount += 1
        return existingByStart[start] ?? []
    }

    func save(_ samples: [HealthSampleDraft]) async throws {
        XCTFail("Preflight must never write HealthKit samples")
    }

    func samplesAuthoredByThisApp(
        externalIDs: Set<String>,
        unitsByType: [HealthQuantityKey: ControlledUnit]
    ) async throws -> [HealthSampleSummary] {
        []
    }
}
