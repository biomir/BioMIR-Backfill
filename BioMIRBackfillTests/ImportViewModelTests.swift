import Foundation
import XCTest
@testable import BioMIRBackfill

@MainActor
final class ImportViewModelTests: XCTestCase {
    func testSourceSelectionStopsAtReviewAndCannotWrite() async throws {
        let gateway = WorkflowFakeGateway()
        let context = try makeContext(gateway: gateway)

        await context.viewModel.selectSource(url: context.sourceURL)

        XCTAssertEqual(context.viewModel.stage, .review)
        XCTAssertEqual(context.viewModel.reviewSummary?.rowCount, 1)
        XCTAssertEqual(context.viewModel.reviewSummary?.supportedMappingCount, 1)
        XCTAssertFalse(context.viewModel.canImport)

        await context.viewModel.performImport()
        XCTAssertEqual(gateway.savedDrafts.count, 0)
        XCTAssertEqual(context.viewModel.stage, .review)
    }

    func testPreflightWarningRemainsVisibleAndImportRequiresExplicitReview() async throws {
        let gateway = WorkflowFakeGateway(readVisibility: .unverifiable)
        let context = try makeContext(gateway: gateway)

        await context.viewModel.selectSource(url: context.sourceURL)
        context.viewModel.continueToPreflight()
        await context.viewModel.runPreflight()

        XCTAssertEqual(context.viewModel.stage, .preflight)
        XCTAssertEqual(context.viewModel.preflightSummary?.eligibleCount, 1)
        XCTAssertEqual(
            context.viewModel.preflightSummary?.visibilityWarning,
            PreflightEngine.unverifiableVisibilityWarning
        )
        XCTAssertFalse(context.viewModel.canImport)

        context.viewModel.setPreflightReviewed(true)
        XCTAssertTrue(context.viewModel.canImport)
    }

    func testFreshPreflightChangeBlocksWriteAndRequiresReviewAgain() async throws {
        let gateway = WorkflowFakeGateway(readVisibility: .unverifiable)
        let context = try makeContext(gateway: gateway)

        await context.viewModel.selectSource(url: context.sourceURL)
        context.viewModel.continueToPreflight()
        await context.viewModel.runPreflight()
        context.viewModel.setPreflightReviewed(true)
        XCTAssertTrue(context.viewModel.canImport)

        gateway.existingSamplesToReturn = [gateway.existingSample()]
        await context.viewModel.performImport()

        XCTAssertEqual(gateway.savedDrafts.count, 0)
        XCTAssertFalse(context.viewModel.preflightReviewed)
        XCTAssertEqual(context.viewModel.preflightSummary?.existingCount, 1)
        XCTAssertEqual(context.viewModel.stage, .preflight)
        XCTAssertNotNil(context.viewModel.errorMessage)
    }

    func testSuccessfulImportRunsVerificationAndProducesAuditBundle() async throws {
        let gateway = WorkflowFakeGateway(readVisibility: .unverifiable)
        let context = try makeContext(gateway: gateway)

        await context.viewModel.selectSource(url: context.sourceURL)
        context.viewModel.continueToPreflight()
        await context.viewModel.runPreflight()
        context.viewModel.setPreflightReviewed(true)
        await context.viewModel.performImport()

        XCTAssertEqual(context.viewModel.stage, .results)
        XCTAssertEqual(gateway.savedDrafts.count, 1)
        XCTAssertEqual(context.viewModel.resultSummary?.importedCount, 1)
        XCTAssertEqual(context.viewModel.resultSummary?.verifiedCount, 1)
        XCTAssertEqual(context.viewModel.resultSummary?.failedVerificationCount, 0)
        XCTAssertEqual(context.viewModel.resultSummary?.isVerifiedComplete, true)
        let auditURL = try XCTUnwrap(context.viewModel.auditBundleURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: auditURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: auditURL.appendingPathComponent("SHA256SUMS.json").path))
    }


    func testHistoricalNoonRepairDeletionUsesControlledScopeAndReportsCount() async throws {
        let gateway = WorkflowFakeGateway()
        gateway.deletedCountToReturn = HistoricalNutritionRepairSummary.expectedLegacySampleCount
        let context = try makeContext(gateway: gateway)

        await context.viewModel.performHistoricalNutritionNoonRepairDeletion()

        let request = try XCTUnwrap(gateway.lastDeletionRequest)
        XCTAssertEqual(request.types, Set(HealthQuantityKey.allCases))
        XCTAssertEqual(request.mappingVersions, Set(["nutrition-v0.1", "carbmanager-total-carb-v1"]))
        XCTAssertEqual(request.classification, "historical-user-controlled-import")
        XCTAssertEqual(context.viewModel.repairSummary?.deletedCount, 43_612)
        XCTAssertEqual(context.viewModel.repairSummary?.matchesExpectedCount, true)
        XCTAssertTrue(gateway.savedDrafts.isEmpty)
    }

    private func makeContext(gateway: WorkflowFakeGateway) throws -> TestContext {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BioMIRBackfill-Task8-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("history.csv")
        try Data("Date,Sodium (mg),Net Carbs (g)\n2025-01-01,1500,20\n".utf8).write(to: sourceURL)

        var calendar = Calendar(identifier: .gregorian)
        let zone = TimeZone(identifier: "America/New_York")!
        calendar.timeZone = zone

        let ledger = try AuditLedger(storageURL: root.appendingPathComponent("audit.jsonl"))
        let journal = try ImportJournal(storageURL: root.appendingPathComponent("journal.jsonl"))
        let exporter = AuditExporter(baseDirectory: root)
        let viewModel = ImportViewModel(
            gateway: gateway,
            auditLedger: ledger,
            journal: journal,
            auditExporter: exporter,
            sourceTimeZone: zone,
            calendar: calendar,
            environmentProvider: {
                ImportManifestEnvironment(
                    appVersion: "0.1",
                    appBuild: "8",
                    osVersion: "test",
                    generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
                )
            }
        )
        return TestContext(viewModel: viewModel, sourceURL: sourceURL)
    }
}

private struct TestContext {
    let viewModel: ImportViewModel
    let sourceURL: URL
}

private final class WorkflowFakeGateway: HealthStoreGateway, @unchecked Sendable {
    var isHealthDataAvailable = true
    var readVisibilityValue: HealthReadVisibility
    var writeStatuses: [HealthQuantityKey: HealthWriteAuthorizationStatus] = [:]
    var existingSamplesToReturn: [HealthSampleSummary] = []
    var savedDrafts: [HealthSampleDraft] = []
    var deletedCountToReturn = 0
    var lastDeletionRequest: HistoricalSampleDeletionRequest?

    init(readVisibility: HealthReadVisibility = .unverifiable) {
        self.readVisibilityValue = readVisibility
    }

    func requestAuthorization(read: Set<HealthQuantityKey>, write: Set<HealthQuantityKey>) async throws {
        for identifier in write { writeStatuses[identifier] = .sharingAuthorized }
    }

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
        existingSamplesToReturn
    }

    func save(_ samples: [HealthSampleDraft]) async throws {
        savedDrafts.append(contentsOf: samples)
    }

    func samplesAuthoredByThisApp(
        externalIDs: Set<String>,
        unitsByType: [HealthQuantityKey: ControlledUnit]
    ) async throws -> [HealthSampleSummary] {
        savedDrafts.compactMap { draft in
            guard let externalID = draft.externalID, externalIDs.contains(externalID) else { return nil }
            return HealthSampleSummary(
                uuid: UUID(),
                typeIdentifier: draft.typeIdentifier,
                value: draft.value,
                unit: draft.unit,
                startDate: draft.startDate,
                endDate: draft.endDate,
                sourceBundleIdentifier: "co.biomir.backfill",
                externalID: externalID,
                wasUserEntered: draft.wasUserEntered,
                stringMetadata: draft.stringMetadata
            )
        }
    }

    func deleteAppAuthoredSamples(
        matching request: HistoricalSampleDeletionRequest
    ) async throws -> Int {
        lastDeletionRequest = request
        return deletedCountToReturn
    }

    func existingSample() -> HealthSampleSummary {
        HealthSampleSummary(
            uuid: UUID(),
            typeIdentifier: .dietarySodium,
            value: 1400,
            unit: .milligram,
            startDate: Date(timeIntervalSince1970: 1_735_700_400),
            endDate: Date(timeIntervalSince1970: 1_735_786_800),
            sourceBundleIdentifier: "com.example.other",
            externalID: nil,
            wasUserEntered: nil,
            stringMetadata: [:]
        )
    }
}
