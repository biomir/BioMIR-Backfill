import Foundation

private enum HarnessError: Error { case plannedFailure }

private final class HarnessGateway: HealthStoreGateway, @unchecked Sendable {
    var isHealthDataAvailable = true
    var writeStatus: HealthWriteAuthorizationStatus = .sharingAuthorized
    var failOnSaveCall: Int?
    var hideExistingDaySamples = false
    private(set) var saveCallCount = 0
    private(set) var saveBatchSizes: [Int] = []
    private(set) var savedDrafts: [HealthSampleDraft] = []

    init(failOnSaveCall: Int? = nil) { self.failOnSaveCall = failOnSaveCall }
    func resetSaveCallCounter() { saveCallCount = 0 }
    func requestAuthorization(read: Set<HealthQuantityKey>, write: Set<HealthQuantityKey>) async throws {}
    func writeAuthorizationStatus(for identifier: HealthQuantityKey) -> HealthWriteAuthorizationStatus { writeStatus }
    func readVisibility(for identifiers: Set<HealthQuantityKey>) async throws -> HealthReadVisibility { .unverifiable }

    func existingSamples(type: HealthQuantityKey, unit: ControlledUnit, start: Date, end: Date) async throws -> [HealthSampleSummary] {
        if hideExistingDaySamples { return [] }
        return savedDrafts.compactMap { draft in
            guard draft.typeIdentifier == type, draft.startDate >= start, draft.startDate < end else { return nil }
            return summary(draft)
        }
    }

    func save(_ samples: [HealthSampleDraft]) async throws {
        saveCallCount += 1
        saveBatchSizes.append(samples.count)
        if failOnSaveCall == saveCallCount { throw HarnessError.plannedFailure }
        savedDrafts.append(contentsOf: samples)
    }

    func samplesAuthoredByThisApp(externalIDs: Set<String>, unitsByType: [HealthQuantityKey : ControlledUnit]) async throws -> [HealthSampleSummary] {
        savedDrafts.compactMap { draft in
            guard let id = draft.externalID, externalIDs.contains(id) else { return nil }
            return summary(draft)
        }
    }

    private func summary(_ draft: HealthSampleDraft) -> HealthSampleSummary {
        HealthSampleSummary(
            uuid: UUID(), typeIdentifier: draft.typeIdentifier, value: draft.value, unit: draft.unit,
            startDate: draft.startDate, endDate: draft.endDate,
            sourceBundleIdentifier: "co.biomir.backfill", externalID: draft.externalID
        )
    }
}

@main
struct Task6PortableHarness {
    static func main() async throws {
        try await auditAndJournalPersistence()
        try await interruptedBatchAndResume()
        try await authorizationRecheck()
        try await deterministicRepeatProtection()
        try await postSaveAuditFailureSemantics()
        try await sourceHashHardStop()
        print("TASK 6 PORTABLE COORDINATION: PASS")
    }

    private static func auditAndJournalPersistence() async throws {
        let auditURL = FileManager.default.temporaryDirectory.appendingPathComponent("task6-audit-\(UUID().uuidString).jsonl")
        let journalURL = FileManager.default.temporaryDirectory.appendingPathComponent("task6-journal-\(UUID().uuidString).jsonl")
        defer {
            try? FileManager.default.removeItem(at: auditURL)
            try? FileManager.default.removeItem(at: journalURL)
        }
        let runID = UUID()
        do {
            let ledger = try AuditLedger(storageURL: auditURL)
            try await ledger.append(AuditRecord(
                eventID: UUID(), runID: runID, subjectKey: "a", externalID: "a", rowNumber: 1,
                sourceColumn: "Sodium (mg)", sourceDate: "2025-01-01", healthIdentifier: "dietarySodium",
                disposition: .imported, batchID: UUID(), timestamp: Date(timeIntervalSince1970: 1), detail: nil
            ))
            try await ledger.append(AuditRecord(
                eventID: UUID(), runID: runID, subjectKey: "a", externalID: "a", rowNumber: 1,
                sourceColumn: "Sodium (mg)", sourceDate: "2025-01-01", healthIdentifier: "dietarySodium",
                disposition: .verificationFailed, batchID: UUID(), timestamp: Date(timeIntervalSince1970: 2), detail: "mismatch"
            ))
        }
        let reopenedLedger = try AuditLedger(storageURL: auditURL)
        let summary = await reopenedLedger.summary(for: runID)
        precondition(summary.totalSubjects == 1 && summary.count(.verificationFailed) == 1)

        let batch1 = UUID(), batch2 = UUID()
        do {
            let journal = try ImportJournal(storageURL: journalURL)
            try await journal.append(.started(eventID: UUID(), runID: runID, batchID: batch1, sourceSHA256: "abc", rangeStart: 0, rangeEndExclusive: 100, plannedExternalIDs: ["a"], timestamp: Date(timeIntervalSince1970: 1)))
            try await journal.append(.succeeded(eventID: UUID(), runID: runID, batchID: batch1, timestamp: Date(timeIntervalSince1970: 2)))
            try await journal.append(.started(eventID: UUID(), runID: runID, batchID: batch2, sourceSHA256: "abc", rangeStart: 100, rangeEndExclusive: 200, plannedExternalIDs: ["b"], timestamp: Date(timeIntervalSince1970: 3)))
            try await journal.append(.failed(eventID: UUID(), runID: runID, batchID: batch2, timestamp: Date(timeIntervalSince1970: 4), errorDescription: "planned"))
        }
        let reopenedJournal = try ImportJournal(storageURL: journalURL)
        let states = await reopenedJournal.batchStates()
        precondition(states.count == 2 && states[0].writeStatus == .succeeded && states[1].writeStatus == .failed)
    }

    private static func interruptedBatchAndResume() async throws {
        let mapping = makeMapping(count: 250)
        let manifest = makeManifest(rowCount: 250)
        let gateway = HarnessGateway(failOnSaveCall: 2)
        let journal = try ImportJournal(storageURL: nil)
        let ledger = try AuditLedger(storageURL: nil)
        let coordinator = makeCoordinator(manifest: manifest, journal: journal, ledger: ledger)
        let first = try await PreflightEngine.run(mappingResult: mapping, manifest: manifest, calendar: calendar(), gateway: gateway)
        do {
            _ = try await coordinator.import(report: first, batchSize: 100, gateway: gateway)
            preconditionFailure("expected planned batch failure")
        } catch ImportCoordinatorError.batchWriteFailed {}
        precondition(gateway.saveBatchSizes == [100, 100])
        precondition(gateway.savedDrafts.count == 100)
        let states = await journal.batchStates()
        precondition(states.count == 2 && states[0].writeStatus == .succeeded && states[1].writeStatus == .failed)

        gateway.failOnSaveCall = nil
        gateway.resetSaveCallCounter()
        let fresh = try await PreflightEngine.run(mappingResult: mapping, manifest: manifest, calendar: calendar(), gateway: gateway)
        precondition(fresh.count(.skippedExisting) == 100 && fresh.eligible.count == 150)
        let resumed = try await coordinator.import(report: fresh, batchSize: 100, gateway: gateway)
        precondition(resumed.importedCount == 150)
        precondition(Array(gateway.saveBatchSizes.suffix(2)) == [100, 50])
        precondition(gateway.savedDrafts.count == 250)
    }

    private static func authorizationRecheck() async throws {
        let mapping = makeMapping(count: 1), manifest = makeManifest(rowCount: 1)
        let gateway = HarnessGateway()
        let report = try await PreflightEngine.run(mappingResult: mapping, manifest: manifest, calendar: calendar(), gateway: gateway)
        gateway.writeStatus = .sharingDenied
        let coordinator = makeCoordinator(manifest: manifest, journal: try ImportJournal(storageURL: nil), ledger: try AuditLedger(storageURL: nil))
        let result = try await coordinator.import(report: report, gateway: gateway)
        precondition(result.importedCount == 0 && result.authorizationBlockedCount == 1 && gateway.savedDrafts.isEmpty)
    }

    private static func deterministicRepeatProtection() async throws {
        let mapping = makeMapping(count: 1), manifest = makeManifest(rowCount: 1)
        let gateway = HarnessGateway()
        let coordinator = makeCoordinator(manifest: manifest, journal: try ImportJournal(storageURL: nil), ledger: try AuditLedger(storageURL: nil))
        let first = try await PreflightEngine.run(mappingResult: mapping, manifest: manifest, calendar: calendar(), gateway: gateway)
        let r1 = try await coordinator.import(report: first, gateway: gateway)
        precondition(r1.importedCount == 1 && gateway.savedDrafts.count == 1)
        gateway.hideExistingDaySamples = true
        let second = try await PreflightEngine.run(mappingResult: mapping, manifest: manifest, calendar: calendar(), gateway: gateway)
        precondition(second.eligible.count == 1)
        let r2 = try await coordinator.import(report: second, gateway: gateway)
        precondition(r2.importedCount == 0 && r2.skippedExistingCount == 1 && gateway.savedDrafts.count == 1)
    }


    private static func postSaveAuditFailureSemantics() async throws {
        let mapping = makeMapping(count: 1), manifest = makeManifest(rowCount: 1), gateway = HarnessGateway()
        let report = try await PreflightEngine.run(mappingResult: mapping, manifest: manifest, calendar: calendar(), gateway: gateway)
        let journal = try ImportJournal(storageURL: nil)
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("task6-ledger-blocker-\(UUID().uuidString)")
        _ = FileManager.default.createFile(atPath: blocker.path, contents: Data("block".utf8))
        defer { try? FileManager.default.removeItem(at: blocker) }
        let ledger = try AuditLedger(storageURL: blocker.appendingPathComponent("audit.jsonl"))
        let coordinator = makeCoordinator(manifest: manifest, journal: journal, ledger: ledger)
        do {
            _ = try await coordinator.import(report: report, gateway: gateway)
            preconditionFailure("expected local audit persistence failure")
        } catch ImportCoordinatorError.batchWriteFailed {
            preconditionFailure("successful HealthKit save was mislabeled as batch write failure")
        } catch {}
        precondition(gateway.savedDrafts.count == 1)
        let states = await journal.batchStates()
        precondition(states.count == 1 && states[0].writeStatus == .succeeded)
    }

    private static func sourceHashHardStop() async throws {
        let mapping = makeMapping(count: 1), manifest = makeManifest(rowCount: 1), gateway = HarnessGateway()
        let report = try await PreflightEngine.run(mappingResult: mapping, manifest: manifest, calendar: calendar(), gateway: gateway)
        let coordinator = ImportCoordinator(
            calendar: calendar(), journal: try ImportJournal(storageURL: nil), auditLedger: try AuditLedger(storageURL: nil),
            currentSourceSHA256: { String(repeating: "f", count: 64) }
        )
        do {
            _ = try await coordinator.import(report: report, gateway: gateway)
            preconditionFailure("expected source mismatch")
        } catch SourceIntegrityError.sourceChanged {}
        precondition(gateway.savedDrafts.isEmpty)
    }

    private static func makeCoordinator(manifest: ImportManifest, journal: ImportJournal, ledger: AuditLedger) -> ImportCoordinator {
        ImportCoordinator(calendar: calendar(), journal: journal, auditLedger: ledger, currentSourceSHA256: { manifest.sourceSHA256 })
    }

    private static func calendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private static func makeManifest(rowCount: Int) -> ImportManifest {
        ImportManifest(
            sourceFilename: "history.csv", sourceSHA256: String(repeating: "a", count: 64), sourceByteCount: 100,
            rowCount: rowCount, encoding: "UTF-8", sourceTimeZoneIdentifier: "America/New_York",
            sourceDateStart: "2024-01-01", sourceDateEnd: "2025-12-31", headers: ["Date", "Sodium (mg)"],
            schemaSHA256: String(repeating: "b", count: 64), parserVersion: "csv-v0.1", mappingVersion: "nutrition-v0.1",
            appVersion: "1.0", appBuild: "1", osVersion: "26.2", generatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func makeMapping(count: Int) -> MappingResult {
        let c = calendar()
        let start = c.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let candidates = (0..<count).map { index -> MappedCandidate in
            let date = c.date(byAdding: .day, value: index, to: start)!
            let components = c.dateComponents([.year, .month, .day], from: date)
            return MappedCandidate(
                rowNumber: index + 2, sourceDate: components, sourceColumn: "Sodium (mg)",
                healthIdentifier: .dietarySodium, cellState: .value(Double(1000 + index)), originalUnit: "mg",
                healthUnit: .milligram, normalizedValue: Double(1000 + index), transformationID: "identity", transformationVersion: "1"
            )
        }
        return MappingResult(mappedCandidates: candidates, unsupportedFields: [], registryVersion: "nutrition-v0.1")
    }
}
