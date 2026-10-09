import Foundation
import XCTest
@testable import BioMIRBackfill

final class AuditLedgerTests: XCTestCase {
    func testDeterministicExternalUUIDIsStableAndSensitiveToControlledInputs() {
        let manifest = makeManifest(sourceSHA256: String(repeating: "a", count: 64), mappingVersion: "nutrition-v0.1")
        let candidate = makeCandidate(rowNumber: 7, day: 14, type: .dietarySodium)

        let first = ProvenanceService.externalUUID(for: candidate, manifest: manifest)
        let second = ProvenanceService.externalUUID(for: candidate, manifest: manifest)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.split(separator: "-")[2].first, "8", "Custom SHA-256 identity must use UUIDv8 layout")

        let changedSource = ProvenanceService.externalUUID(
            for: candidate,
            manifest: makeManifest(sourceSHA256: String(repeating: "b", count: 64), mappingVersion: "nutrition-v0.1")
        )
        XCTAssertNotEqual(first, changedSource)

        let changedRow = ProvenanceService.externalUUID(
            for: makeCandidate(rowNumber: 8, day: 14, type: .dietarySodium),
            manifest: manifest
        )
        XCTAssertNotEqual(first, changedRow)

        let changedType = ProvenanceService.externalUUID(
            for: makeCandidate(rowNumber: 7, day: 14, type: .dietaryPotassium),
            manifest: manifest
        )
        XCTAssertNotEqual(first, changedType)

        let changedDate = ProvenanceService.externalUUID(
            for: makeCandidate(rowNumber: 7, day: 15, type: .dietarySodium),
            manifest: manifest
        )
        XCTAssertNotEqual(first, changedDate)

        let changedMapping = ProvenanceService.externalUUID(
            for: candidate,
            manifest: makeManifest(sourceSHA256: String(repeating: "a", count: 64), mappingVersion: "nutrition-v0.2")
        )
        XCTAssertNotEqual(first, changedMapping)
    }

    func testProvenanceMetadataContainsControlledSourceAndBatchContext() {
        let batchID = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
        let manifest = makeManifest(sourceSHA256: String(repeating: "c", count: 64), mappingVersion: "nutrition-v0.1")
        let candidate = makeCandidate(rowNumber: 42, day: 9, type: .dietarySodium)
        let context = ProvenanceContext(batchID: batchID, candidate: candidate, manifest: manifest)

        let metadata = ProvenanceService.stringMetadata(for: context)

        XCTAssertEqual(metadata[ProvenanceService.MetadataKey.batchUUID], batchID.uuidString.lowercased())
        XCTAssertEqual(metadata[ProvenanceService.MetadataKey.schemaVersion], ProvenanceService.schemaVersion)
        XCTAssertEqual(metadata[ProvenanceService.MetadataKey.mappingVersion], "nutrition-v0.1")
        XCTAssertEqual(metadata[ProvenanceService.MetadataKey.sourceCalendarDate], "2025-01-09")
        XCTAssertEqual(metadata[ProvenanceService.MetadataKey.sourceField], "Sodium (mg)")
        XCTAssertEqual(metadata[ProvenanceService.MetadataKey.sourceUnit], "mg")
        XCTAssertEqual(metadata[ProvenanceService.MetadataKey.transformationID], "identity")
        XCTAssertEqual(metadata[ProvenanceService.MetadataKey.sourceSHA256], String(repeating: "c", count: 64))
        XCTAssertEqual(metadata[ProvenanceService.MetadataKey.classification], ProvenanceService.historicalImportClassification)
    }

    func testAuditSummaryUsesOneLatestDispositionPerSubjectWithinRunAndReconciles() async throws {
        let ledger = try AuditLedger(storageURL: nil)
        let runID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let otherRun = UUID(uuidString: "66666666-7777-4888-8999-AAAAAAAAAAAA")!

        try await ledger.append(AuditRecord(
            eventID: UUID(), runID: runID, subjectKey: "candidate-a", externalID: "candidate-a",
            rowNumber: 1, sourceColumn: "Sodium (mg)", sourceDate: "2025-01-01",
            healthIdentifier: HealthQuantityKey.dietarySodium.rawValue, disposition: .imported,
            batchID: UUID(), timestamp: Date(timeIntervalSince1970: 10), detail: nil
        ))
        try await ledger.append(AuditRecord(
            eventID: UUID(), runID: runID, subjectKey: "candidate-a", externalID: "candidate-a",
            rowNumber: 1, sourceColumn: "Sodium (mg)", sourceDate: "2025-01-01",
            healthIdentifier: HealthQuantityKey.dietarySodium.rawValue, disposition: .verificationFailed,
            batchID: UUID(), timestamp: Date(timeIntervalSince1970: 20), detail: "mismatch"
        ))
        try await ledger.append(AuditRecord(
            eventID: UUID(), runID: runID, subjectKey: "candidate-b", externalID: "candidate-b",
            rowNumber: 2, sourceColumn: "Sodium (mg)", sourceDate: "2025-01-02",
            healthIdentifier: HealthQuantityKey.dietarySodium.rawValue, disposition: .skippedExisting,
            batchID: nil, timestamp: Date(timeIntervalSince1970: 30), detail: nil
        ))
        try await ledger.append(AuditRecord(
            eventID: UUID(), runID: otherRun, subjectKey: "candidate-c", externalID: "candidate-c",
            rowNumber: 3, sourceColumn: "Sodium (mg)", sourceDate: "2025-01-03",
            healthIdentifier: HealthQuantityKey.dietarySodium.rawValue, disposition: .imported,
            batchID: UUID(), timestamp: Date(timeIntervalSince1970: 40), detail: nil
        ))

        let summary = await ledger.summary(for: runID)
        XCTAssertEqual(summary.totalSubjects, 2)
        XCTAssertEqual(summary.count(.verificationFailed), 1)
        XCTAssertEqual(summary.count(.skippedExisting), 1)
        XCTAssertEqual(summary.count(.imported), 0)
        XCTAssertEqual(summary.counts.values.reduce(0, +), summary.totalSubjects)
    }


    func testAuditLedgerPersistsAppendOnlyEventsAcrossReopen() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit-ledger-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let runID = UUID()

        do {
            let ledger = try AuditLedger(storageURL: url)
            try await ledger.append(AuditRecord(
                eventID: UUID(), runID: runID, subjectKey: "persist-a", externalID: "persist-a",
                rowNumber: 1, sourceColumn: "Sodium (mg)", sourceDate: "2025-01-01",
                healthIdentifier: HealthQuantityKey.dietarySodium.rawValue, disposition: .imported,
                batchID: UUID(), timestamp: Date(timeIntervalSince1970: 1), detail: nil
            ))
        }

        let reopened = try AuditLedger(storageURL: url)
        let summary = await reopened.summary(for: runID)
        XCTAssertEqual(summary.totalSubjects, 1)
        XCTAssertEqual(summary.count(.imported), 1)
    }

    func testImportJournalPersistsEventsAndDerivesLatestBatchStateAcrossReopen() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-journal-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let runID = UUID()
        let batchID = UUID()

        do {
            let journal = try ImportJournal(storageURL: url)
            try await journal.append(.started(
                eventID: UUID(), runID: runID, batchID: batchID, sourceSHA256: "abc",
                rangeStart: 0, rangeEndExclusive: 100, plannedExternalIDs: ["a", "b"],
                timestamp: Date(timeIntervalSince1970: 1)
            ))
            try await journal.append(.failed(
                eventID: UUID(), runID: runID, batchID: batchID,
                timestamp: Date(timeIntervalSince1970: 2), errorDescription: "planned"
            ))
        }

        let reopened = try ImportJournal(storageURL: url)
        let states = await reopened.batchStates()
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states[0].batchID, batchID)
        XCTAssertEqual(states[0].plannedCount, 2)
        XCTAssertEqual(states[0].writeStatus, .failed)
    }

    private func makeManifest(sourceSHA256: String, mappingVersion: String) -> ImportManifest {
        ImportManifest(
            sourceFilename: "history.csv", sourceSHA256: sourceSHA256, sourceByteCount: 10,
            rowCount: 1, encoding: "UTF-8", sourceTimeZoneIdentifier: "America/New_York",
            sourceDateStart: "2025-01-01", sourceDateEnd: "2025-01-01", headers: ["Date", "Sodium (mg)"],
            schemaSHA256: String(repeating: "d", count: 64), parserVersion: "csv-v0.1", mappingVersion: mappingVersion,
            appVersion: "1.0", appBuild: "1", osVersion: "26.2", generatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeCandidate(rowNumber: Int, day: Int, type: HealthQuantityKey) -> MappedCandidate {
        MappedCandidate(
            rowNumber: rowNumber,
            sourceDate: DateComponents(year: 2025, month: 1, day: day),
            sourceColumn: "Sodium (mg)", healthIdentifier: type, cellState: .value(1500),
            originalUnit: "mg", healthUnit: .milligram, normalizedValue: 1500,
            transformationID: "identity", transformationVersion: "1"
        )
    }
}
