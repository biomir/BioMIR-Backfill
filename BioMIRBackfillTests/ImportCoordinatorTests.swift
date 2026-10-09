import Foundation
import XCTest
@testable import BioMIRBackfill

final class ImportCoordinatorTests: XCTestCase {
    func testCoordinatorUsesBoundedBatchesAndPersistsInterruptedProgress() async throws {
        let mapping = makeMapping(count: 250)
        let manifest = makeManifest(rowCount: 250)
        let gateway = CoordinatorFakeGateway(failOnSaveCall: 2)
        let report = try await PreflightEngine.run(mappingResult: mapping, manifest: manifest, calendar: makeCalendar(), gateway: gateway)
        let journal = try ImportJournal(storageURL: nil)
        let ledger = try AuditLedger(storageURL: nil)
        let coordinator = makeCoordinator(manifest: manifest, journal: journal, ledger: ledger)

        do {
            _ = try await coordinator.import(report: report, batchSize: 100, gateway: gateway)
            XCTFail("Expected second batch to fail")
        } catch ImportCoordinatorError.batchWriteFailed {
            // expected
        }

        XCTAssertEqual(gateway.saveBatchSizes, [100, 100])
        let states = await journal.batchStates()
        XCTAssertEqual(states.count, 2)
        XCTAssertEqual(states[0].writeStatus, .succeeded)
        XCTAssertEqual(states[0].plannedCount, 100)
        XCTAssertEqual(states[1].writeStatus, .failed)
        XCTAssertEqual(states[1].plannedCount, 100)
        XCTAssertEqual(gateway.savedDrafts.count, 100)
    }

    func testResumeRequiresFreshPreflightAndSchedulesOnlyStillMissingRecords() async throws {
        let mapping = makeMapping(count: 250)
        let manifest = makeManifest(rowCount: 250)
        let gateway = CoordinatorFakeGateway(failOnSaveCall: 2)
        let journal = try ImportJournal(storageURL: nil)
        let ledger = try AuditLedger(storageURL: nil)
        let coordinator = makeCoordinator(manifest: manifest, journal: journal, ledger: ledger)

        let firstReport = try await PreflightEngine.run(mappingResult: mapping, manifest: manifest, calendar: makeCalendar(), gateway: gateway)
        do {
            _ = try await coordinator.import(report: firstReport, batchSize: 100, gateway: gateway)
            XCTFail("Expected planned interruption")
        } catch ImportCoordinatorError.batchWriteFailed {
            // expected
        }
        XCTAssertEqual(gateway.savedDrafts.count, 100)

        gateway.failOnSaveCall = nil
        gateway.resetSaveCallCounter()
        let resumedReport = try await PreflightEngine.run(mappingResult: mapping, manifest: manifest, calendar: makeCalendar(), gateway: gateway)
        XCTAssertEqual(resumedReport.count(.skippedExisting), 100)
        XCTAssertEqual(resumedReport.eligible.count, 150)

        let resumedResult = try await coordinator.import(report: resumedReport, batchSize: 100, gateway: gateway)
        XCTAssertEqual(resumedResult.importedCount, 150)
        XCTAssertEqual(gateway.saveBatchSizes.suffix(2), [100, 50])
        XCTAssertEqual(gateway.savedDrafts.count, 250)
    }

    func testSourceHashMismatchHardStopsBeforeAnyWrite() async throws {
        let mapping = makeMapping(count: 1)
        let manifest = makeManifest(rowCount: 1)
        let gateway = CoordinatorFakeGateway()
        let report = try await PreflightEngine.run(mappingResult: mapping, manifest: manifest, calendar: makeCalendar(), gateway: gateway)
        let journal = try ImportJournal(storageURL: nil)
        let ledger = try AuditLedger(storageURL: nil)
        let coordinator = ImportCoordinator(
            calendar: makeCalendar(), journal: journal, auditLedger: ledger,
            currentSourceSHA256: { String(repeating: "f", count: 64) }
        )

        do {
            _ = try await coordinator.import(report: report, gateway: gateway)
            XCTFail("Expected source integrity failure")
        } catch SourceIntegrityError.sourceChanged {
            // expected
        }
        XCTAssertTrue(gateway.savedDrafts.isEmpty)
        let states = await journal.batchStates()
        XCTAssertTrue(states.isEmpty)
    }

    func testCoordinatorRechecksWriteAuthorizationAfterPreflight() async throws {
        let mapping = makeMapping(count: 1)
        let manifest = makeManifest(rowCount: 1)
        let gateway = CoordinatorFakeGateway()
        let report = try await PreflightEngine.run(mappingResult: mapping, manifest: manifest, calendar: makeCalendar(), gateway: gateway)
        gateway.writeStatus = .sharingDenied
        let journal = try ImportJournal(storageURL: nil)
        let ledger = try AuditLedger(storageURL: nil)
        let coordinator = makeCoordinator(manifest: manifest, journal: journal, ledger: ledger)

        let result = try await coordinator.import(report: report, gateway: gateway)
        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.authorizationBlockedCount, 1)
        XCTAssertTrue(gateway.savedDrafts.isEmpty)
        let summary = await ledger.summary(for: result.runID)
        XCTAssertEqual(summary.count(.authorizationBlocked), 1)
    }



    func testPostSaveAuditFailureDoesNotRelabelSuccessfulHealthKitWriteAsFailed() async throws {
        let mapping = makeMapping(count: 1)
        let manifest = makeManifest(rowCount: 1)
        let gateway = CoordinatorFakeGateway()
        let report = try await PreflightEngine.run(
            mappingResult: mapping, manifest: manifest, calendar: makeCalendar(), gateway: gateway
        )
        let journal = try ImportJournal(storageURL: nil)

        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("task6-ledger-blocker-\(UUID().uuidString)")
        _ = FileManager.default.createFile(atPath: blocker.path, contents: Data("block".utf8))
        defer { try? FileManager.default.removeItem(at: blocker) }
        let invalidLedgerURL = blocker.appendingPathComponent("audit.jsonl")
        let ledger = try AuditLedger(storageURL: invalidLedgerURL)
        let coordinator = makeCoordinator(manifest: manifest, journal: journal, ledger: ledger)

        do {
            _ = try await coordinator.import(report: report, gateway: gateway)
            XCTFail("Expected local audit persistence failure after the HealthKit save")
        } catch ImportCoordinatorError.batchWriteFailed {
            XCTFail("A successful HealthKit save must not be relabeled as a batch write failure")
        } catch {
            // Expected: the local audit persistence error propagates after the successful save.
        }

        XCTAssertEqual(gateway.savedDrafts.count, 1)
        let states = await journal.batchStates()
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states[0].writeStatus, .succeeded)
    }

    func testCoordinatorProtectsAgainstRepeatImportUsingDeterministicAppAuthoredIdentity() async throws {
        let mapping = makeMapping(count: 1)
        let manifest = makeManifest(rowCount: 1)
        let gateway = CoordinatorFakeGateway()
        let journal = try ImportJournal(storageURL: nil)
        let ledger = try AuditLedger(storageURL: nil)
        let coordinator = makeCoordinator(manifest: manifest, journal: journal, ledger: ledger)

        let firstReport = try await PreflightEngine.run(
            mappingResult: mapping, manifest: manifest, calendar: makeCalendar(), gateway: gateway
        )
        let firstResult = try await coordinator.import(report: firstReport, gateway: gateway)
        XCTAssertEqual(firstResult.importedCount, 1)
        XCTAssertEqual(gateway.savedDrafts.count, 1)

        gateway.hideExistingDaySamples = true
        let secondReport = try await PreflightEngine.run(
            mappingResult: mapping, manifest: manifest, calendar: makeCalendar(), gateway: gateway
        )
        XCTAssertEqual(secondReport.eligible.count, 1, "Simulate an unreadable day-level collision query")

        let secondResult = try await coordinator.import(report: secondReport, gateway: gateway)
        XCTAssertEqual(secondResult.importedCount, 0)
        XCTAssertEqual(secondResult.skippedExistingCount, 1)
        XCTAssertEqual(gateway.savedDrafts.count, 1, "Repeat import must not append the same app-authored identity")
    }


    func testImportedHistoricalAggregateUsesNoonPointAnchor() async throws {
        let mapping = makeMapping(count: 1)
        let manifest = makeManifest(rowCount: 1)
        let gateway = CoordinatorFakeGateway()
        let report = try await PreflightEngine.run(
            mappingResult: mapping, manifest: manifest, calendar: makeCalendar(), gateway: gateway
        )
        let coordinator = makeCoordinator(
            manifest: manifest,
            journal: try ImportJournal(storageURL: nil),
            ledger: try AuditLedger(storageURL: nil)
        )

        let result = try await coordinator.import(report: report, gateway: gateway)
        XCTAssertEqual(result.importedCount, 1)
        let draft = try XCTUnwrap(gateway.savedDrafts.first)
        XCTAssertEqual(draft.startDate, draft.endDate)
        let parts = makeCalendar().dateComponents([.hour, .minute, .second], from: draft.startDate)
        XCTAssertEqual(parts.hour, 12)
        XCTAssertEqual(parts.minute, 0)
        XCTAssertEqual(parts.second, 0)
        XCTAssertEqual(draft.stringMetadata[ProvenanceService.MetadataKey.timeAnchorPolicy], "daily-aggregate-noon-v1")
    }

    func testBatchSizeMustRemainWithinControlledRange() async throws {
        let mapping = makeMapping(count: 1)
        let manifest = makeManifest(rowCount: 1)
        let gateway = CoordinatorFakeGateway()
        let report = try await PreflightEngine.run(mappingResult: mapping, manifest: manifest, calendar: makeCalendar(), gateway: gateway)
        let coordinator = makeCoordinator(
            manifest: manifest,
            journal: try ImportJournal(storageURL: nil),
            ledger: try AuditLedger(storageURL: nil)
        )

        for invalid in [99, 251] {
            do {
                _ = try await coordinator.import(report: report, batchSize: invalid, gateway: gateway)
                XCTFail("Expected invalid batch size \(invalid)")
            } catch ImportCoordinatorError.invalidBatchSize(let value) {
                XCTAssertEqual(value, invalid)
            }
        }
    }

    private func makeCoordinator(manifest: ImportManifest, journal: ImportJournal, ledger: AuditLedger) -> ImportCoordinator {
        ImportCoordinator(
            calendar: makeCalendar(), journal: journal, auditLedger: ledger,
            currentSourceSHA256: { manifest.sourceSHA256 }
        )
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func makeManifest(rowCount: Int) -> ImportManifest {
        ImportManifest(
            sourceFilename: "history.csv", sourceSHA256: String(repeating: "a", count: 64), sourceByteCount: 100,
            rowCount: rowCount, encoding: "UTF-8", sourceTimeZoneIdentifier: "America/New_York",
            sourceDateStart: "2024-01-01", sourceDateEnd: "2025-12-31", headers: ["Date", "Sodium (mg)"],
            schemaSHA256: String(repeating: "b", count: 64), parserVersion: "csv-v0.1", mappingVersion: "nutrition-v0.1",
            appVersion: "1.0", appBuild: "1", osVersion: "26.2", generatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeMapping(count: Int) -> MappingResult {
        let calendar = makeCalendar()
        let start = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let candidates = (0..<count).map { index -> MappedCandidate in
            let date = calendar.date(byAdding: .day, value: index, to: start)!
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            return MappedCandidate(
                rowNumber: index + 2, sourceDate: components, sourceColumn: "Sodium (mg)",
                healthIdentifier: .dietarySodium, cellState: .value(Double(1000 + index)),
                originalUnit: "mg", healthUnit: .milligram, normalizedValue: Double(1000 + index),
                transformationID: "identity", transformationVersion: "1"
            )
        }
        return MappingResult(mappedCandidates: candidates, unsupportedFields: [], registryVersion: "nutrition-v0.1")
    }
}

private enum CoordinatorFakeError: Error { case plannedFailure }

private final class CoordinatorFakeGateway: HealthStoreGateway, @unchecked Sendable {
    var isHealthDataAvailable = true
    var writeStatus: HealthWriteAuthorizationStatus = .sharingAuthorized
    var failOnSaveCall: Int?
    private(set) var saveCallCount = 0
    private(set) var saveBatchSizes: [Int] = []
    private(set) var savedDrafts: [HealthSampleDraft] = []
    var hideExistingDaySamples = false

    init(failOnSaveCall: Int? = nil) {
        self.failOnSaveCall = failOnSaveCall
    }

    func resetSaveCallCounter() { saveCallCount = 0 }

    func requestAuthorization(read: Set<HealthQuantityKey>, write: Set<HealthQuantityKey>) async throws {}

    func writeAuthorizationStatus(for identifier: HealthQuantityKey) -> HealthWriteAuthorizationStatus { writeStatus }

    func readVisibility(for identifiers: Set<HealthQuantityKey>) async throws -> HealthReadVisibility { .unverifiable }

    func existingSamples(type: HealthQuantityKey, unit: ControlledUnit, start: Date, end: Date) async throws -> [HealthSampleSummary] {
        if hideExistingDaySamples { return [] }
        return savedDrafts.compactMap { draft in
            guard draft.typeIdentifier == type, draft.startDate >= start, draft.startDate < end else { return nil }
            return HealthSampleSummary(
                uuid: UUID(), typeIdentifier: draft.typeIdentifier, value: draft.value, unit: draft.unit,
                startDate: draft.startDate, endDate: draft.endDate, sourceBundleIdentifier: "co.biomir.backfill",
                externalID: draft.externalID, wasUserEntered: true, stringMetadata: draft.stringMetadata
            )
        }
    }

    func save(_ samples: [HealthSampleDraft]) async throws {
        saveCallCount += 1
        saveBatchSizes.append(samples.count)
        if failOnSaveCall == saveCallCount { throw CoordinatorFakeError.plannedFailure }
        savedDrafts.append(contentsOf: samples)
    }

    func samplesAuthoredByThisApp(externalIDs: Set<String>, unitsByType: [HealthQuantityKey : ControlledUnit]) async throws -> [HealthSampleSummary] {
        savedDrafts.compactMap { draft in
            guard let externalID = draft.externalID, externalIDs.contains(externalID) else { return nil }
            return HealthSampleSummary(
                uuid: UUID(), typeIdentifier: draft.typeIdentifier, value: draft.value, unit: draft.unit,
                startDate: draft.startDate, endDate: draft.endDate, sourceBundleIdentifier: "co.biomir.backfill",
                externalID: externalID, wasUserEntered: true, stringMetadata: draft.stringMetadata
            )
        }
    }
}
