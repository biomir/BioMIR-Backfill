import Foundation
import XCTest
@testable import BioMIRBackfill

final class VerificationEngineTests: XCTestCase {
    func testExactMatchProducesVerifiedComplete() async throws {
        let expectation = makeExpectation()
        let gateway = VerificationFakeGateway(samples: [sample(matching: expectation)])
        let ledger = try AuditLedger(storageURL: nil)
        let engine = VerificationEngine(auditLedger: ledger)

        let report = await engine.verify(importResult: makeImportResult(expectations: [expectation]), gateway: gateway)

        XCTAssertTrue(report.isVerifiedComplete)
        XCTAssertEqual(report.expectedCount, 1)
        XCTAssertEqual(report.verifiedCount, 1)
        XCTAssertEqual(report.failedCount, 0)
        XCTAssertEqual(report.items.first?.status, .verified)
        let summary = await ledger.summary(for: report.runID)
        XCTAssertEqual(summary.count(.verificationFailed), 0)
    }

    func testMissingSampleProducesVerificationFailed() async throws {
        let expectation = makeExpectation()
        let ledger = try AuditLedger(storageURL: nil)
        let engine = VerificationEngine(auditLedger: ledger)

        let report = await engine.verify(
            importResult: makeImportResult(expectations: [expectation]),
            gateway: VerificationFakeGateway(samples: [])
        )

        XCTAssertFalse(report.isVerifiedComplete)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertEqual(report.items.first?.failureReasons, [.missingSample])
        let summary = await ledger.summary(for: report.runID)
        XCTAssertEqual(summary.count(.verificationFailed), 1)
    }

    func testWrongValueProducesVerificationFailed() async throws {
        let expectation = makeExpectation()
        var observed = sample(matching: expectation)
        observed = HealthSampleSummary(
            uuid: observed.uuid, typeIdentifier: observed.typeIdentifier,
            value: observed.value + 1, unit: observed.unit,
            startDate: observed.startDate, endDate: observed.endDate,
            sourceBundleIdentifier: observed.sourceBundleIdentifier,
            externalID: observed.externalID, wasUserEntered: observed.wasUserEntered,
            stringMetadata: observed.stringMetadata
        )

        let report = await VerificationEngine().verify(
            importResult: makeImportResult(expectations: [expectation]),
            gateway: VerificationFakeGateway(samples: [observed])
        )

        XCTAssertEqual(report.items.first?.failureReasons, [.valueMismatch])
    }


    func testWrongUnitProducesVerificationFailed() async throws {
        let expectation = makeExpectation()
        let observed = sample(matching: expectation)
        let wrongUnit = HealthSampleSummary(
            uuid: observed.uuid, typeIdentifier: observed.typeIdentifier,
            value: observed.value, unit: .gram,
            startDate: observed.startDate, endDate: observed.endDate,
            sourceBundleIdentifier: observed.sourceBundleIdentifier,
            externalID: observed.externalID, wasUserEntered: observed.wasUserEntered,
            stringMetadata: observed.stringMetadata
        )

        let report = await VerificationEngine().verify(
            importResult: makeImportResult(expectations: [expectation]),
            gateway: VerificationFakeGateway(samples: [wrongUnit])
        )

        XCTAssertEqual(report.items.first?.failureReasons, [.unitMismatch])
    }

    func testWrongTypeProducesVerificationFailed() async throws {
        let expectation = makeExpectation()
        let observed = sample(matching: expectation)
        let wrongType = HealthSampleSummary(
            uuid: observed.uuid, typeIdentifier: .dietaryPotassium,
            value: observed.value, unit: observed.unit,
            startDate: observed.startDate, endDate: observed.endDate,
            sourceBundleIdentifier: observed.sourceBundleIdentifier,
            externalID: observed.externalID, wasUserEntered: observed.wasUserEntered,
            stringMetadata: observed.stringMetadata
        )

        let report = await VerificationEngine().verify(
            importResult: makeImportResult(expectations: [expectation]),
            gateway: VerificationFakeGateway(samples: [wrongType])
        )

        XCTAssertEqual(report.items.first?.failureReasons, [.typeMismatch])
    }

    func testWasUserEnteredMismatchProducesVerificationFailed() async throws {
        let expectation = makeExpectation()
        let observed = sample(matching: expectation)
        let wrongFlag = HealthSampleSummary(
            uuid: observed.uuid, typeIdentifier: observed.typeIdentifier,
            value: observed.value, unit: observed.unit,
            startDate: observed.startDate, endDate: observed.endDate,
            sourceBundleIdentifier: observed.sourceBundleIdentifier,
            externalID: observed.externalID, wasUserEntered: false,
            stringMetadata: observed.stringMetadata
        )

        let report = await VerificationEngine().verify(
            importResult: makeImportResult(expectations: [expectation]),
            gateway: VerificationFakeGateway(samples: [wrongFlag])
        )

        XCTAssertEqual(report.items.first?.failureReasons, [.userEnteredMismatch])
    }

    func testWrongDateIntervalProducesVerificationFailed() async throws {
        let expectation = makeExpectation()
        let observed = sample(matching: expectation)
        let shifted = HealthSampleSummary(
            uuid: observed.uuid, typeIdentifier: observed.typeIdentifier,
            value: observed.value, unit: observed.unit,
            startDate: observed.startDate.addingTimeInterval(3600), endDate: observed.endDate,
            sourceBundleIdentifier: observed.sourceBundleIdentifier,
            externalID: observed.externalID, wasUserEntered: observed.wasUserEntered,
            stringMetadata: observed.stringMetadata
        )

        let report = await VerificationEngine().verify(
            importResult: makeImportResult(expectations: [expectation]),
            gateway: VerificationFakeGateway(samples: [shifted])
        )

        XCTAssertEqual(report.items.first?.failureReasons, [.startDateMismatch])
    }

    func testMissingExternalIdentityProducesVerificationFailed() async throws {
        let expectation = makeExpectation()
        let observed = sample(matching: expectation)
        let missingIdentity = HealthSampleSummary(
            uuid: observed.uuid, typeIdentifier: observed.typeIdentifier,
            value: observed.value, unit: observed.unit,
            startDate: observed.startDate, endDate: observed.endDate,
            sourceBundleIdentifier: observed.sourceBundleIdentifier,
            externalID: nil, wasUserEntered: observed.wasUserEntered,
            stringMetadata: observed.stringMetadata
        )

        let report = await VerificationEngine().verify(
            importResult: makeImportResult(expectations: [expectation]),
            gateway: VerificationFakeGateway(samples: [missingIdentity], bypassExternalIDFilter: true)
        )

        XCTAssertEqual(report.items.first?.failureReasons, [.externalIdentityMismatch])
    }

    func testMissingControlledProvenanceProducesVerificationFailed() async throws {
        let expectation = makeExpectation()
        let observed = sample(matching: expectation)
        var metadata = observed.stringMetadata
        metadata.removeValue(forKey: ProvenanceService.MetadataKey.sourceSHA256)
        let incomplete = HealthSampleSummary(
            uuid: observed.uuid, typeIdentifier: observed.typeIdentifier,
            value: observed.value, unit: observed.unit,
            startDate: observed.startDate, endDate: observed.endDate,
            sourceBundleIdentifier: observed.sourceBundleIdentifier,
            externalID: observed.externalID, wasUserEntered: observed.wasUserEntered,
            stringMetadata: metadata
        )

        let report = await VerificationEngine().verify(
            importResult: makeImportResult(expectations: [expectation]),
            gateway: VerificationFakeGateway(samples: [incomplete])
        )

        XCTAssertEqual(report.items.first?.failureReasons, [.provenanceMismatch])
    }

    func testDuplicateExternalIdentityProducesVerificationFailed() async throws {
        let expectation = makeExpectation()
        let observed = sample(matching: expectation)
        let report = await VerificationEngine().verify(
            importResult: makeImportResult(expectations: [expectation]),
            gateway: VerificationFakeGateway(samples: [observed, observed])
        )

        XCTAssertEqual(report.items.first?.failureReasons, [.duplicateExternalIdentity])
    }

    func testGatewayQueryFailureNeverProducesVerifiedComplete() async throws {
        let expectation = makeExpectation()
        let report = await VerificationEngine().verify(
            importResult: makeImportResult(expectations: [expectation]),
            gateway: VerificationFakeGateway(samples: [], queryError: VerificationFakeError.planned)
        )

        XCTAssertFalse(report.isVerifiedComplete)
        XCTAssertEqual(report.items.first?.failureReasons, [.queryFailed])
    }

    #if canImport(CryptoKit)
    func testAuditExporterWritesRequiredArtifactsAndValidSHA256Hashes() async throws {
        let expectation = makeExpectation()
        let runID = UUID()
        let ledger = try AuditLedger(storageURL: nil)
        try await ledger.append(AuditRecord(
            eventID: UUID(), runID: runID, subjectKey: expectation.draft.externalID!,
            externalID: expectation.draft.externalID, rowNumber: expectation.rowNumber,
            sourceColumn: expectation.sourceColumn, sourceDate: expectation.sourceDate,
            healthIdentifier: expectation.draft.typeIdentifier.rawValue, disposition: .imported,
            batchID: expectation.batchID, timestamp: Date(timeIntervalSince1970: 1), detail: nil
        ))
        let report = VerificationReport(
            runID: runID, generatedAt: Date(timeIntervalSince1970: 2), expectedCount: 1,
            verifiedCount: 1, failedCount: 0, isVerifiedComplete: true,
            items: [VerificationItemResult(
                externalID: expectation.draft.externalID!, rowNumber: expectation.rowNumber,
                sourceColumn: expectation.sourceColumn, sourceDate: expectation.sourceDate,
                healthIdentifier: expectation.draft.typeIdentifier.rawValue,
                status: .verified, failureReasons: [], observedSampleUUID: UUID().uuidString.lowercased()
            )]
        )
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("task7-audit-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let exporter = AuditExporter(baseDirectory: base)

        let bundleURL = try await exporter.export(manifest: makeManifest(), ledger: ledger, verification: report)

        let required = ["manifest.json", "mapping-version.txt", "audit-ledger.jsonl", "verification.json", "SHA256SUMS.json"]
        for name in required {
            XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent(name).path), "Missing \(name)")
        }
        let sumsData = try Data(contentsOf: bundleURL.appendingPathComponent("SHA256SUMS.json"))
        let sums = try JSONDecoder().decode([String: String].self, from: sumsData)
        for name in required where name != "SHA256SUMS.json" {
            let actual = SourceFingerprint.sha256(data: try Data(contentsOf: bundleURL.appendingPathComponent(name)))
            XCTAssertEqual(sums[name], actual, "Hash mismatch for \(name)")
        }
    }

    #endif

    private func makeExpectation() -> ImportedSampleExpectation {
        let batchID = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
        let start = Date(timeIntervalSince1970: 1_735_689_600)
        let end = Date(timeIntervalSince1970: 1_735_776_000)
        let externalID = "12345678-1234-8123-8123-123456789abc"
        let metadata = [
            ProvenanceService.MetadataKey.batchUUID: batchID.uuidString.lowercased(),
            ProvenanceService.MetadataKey.schemaVersion: ProvenanceService.schemaVersion,
            ProvenanceService.MetadataKey.mappingVersion: "nutrition-v0.1",
            ProvenanceService.MetadataKey.sourceSHA256: String(repeating: "a", count: 64)
        ]
        return ImportedSampleExpectation(
            rowNumber: 2, sourceColumn: "Sodium (mg)", sourceDate: "2025-01-01", batchID: batchID,
            draft: HealthSampleDraft(
                typeIdentifier: .dietarySodium, value: 1500, unit: .milligram,
                startDate: start, endDate: end, externalID: externalID,
                wasUserEntered: true, stringMetadata: metadata
            )
        )
    }

    private func sample(matching expectation: ImportedSampleExpectation) -> HealthSampleSummary {
        HealthSampleSummary(
            uuid: UUID(), typeIdentifier: expectation.draft.typeIdentifier,
            value: expectation.draft.value, unit: expectation.draft.unit,
            startDate: expectation.draft.startDate, endDate: expectation.draft.endDate,
            sourceBundleIdentifier: "co.biomir.backfill", externalID: expectation.draft.externalID,
            wasUserEntered: expectation.draft.wasUserEntered,
            stringMetadata: expectation.draft.stringMetadata
        )
    }

    private func makeImportResult(expectations: [ImportedSampleExpectation]) -> ImportResult {
        ImportResult(
            runID: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!,
            importedCount: expectations.count, skippedExistingCount: 0, skippedMissingCount: 0,
            skippedZeroPolicyCount: 0, authorizationBlockedCount: 0,
            externalIDs: expectations.compactMap { $0.draft.externalID },
            verificationExpectations: expectations
        )
    }

    private func makeManifest() -> ImportManifest {
        ImportManifest(
            sourceFilename: "history.csv", sourceSHA256: String(repeating: "a", count: 64), sourceByteCount: 100,
            rowCount: 1, encoding: "UTF-8", sourceTimeZoneIdentifier: "America/New_York",
            sourceDateStart: "2025-01-01", sourceDateEnd: "2025-01-01", headers: ["Date", "Sodium (mg)"],
            schemaSHA256: String(repeating: "b", count: 64), parserVersion: "csv-v0.1", mappingVersion: "nutrition-v0.1",
            appVersion: "1.0", appBuild: "1", osVersion: "26.2", generatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

private enum VerificationFakeError: Error { case planned }

private final class VerificationFakeGateway: HealthStoreGateway, @unchecked Sendable {
    var isHealthDataAvailable = true
    var samples: [HealthSampleSummary]
    var queryError: Error?
    var bypassExternalIDFilter: Bool

    init(samples: [HealthSampleSummary], queryError: Error? = nil, bypassExternalIDFilter: Bool = false) {
        self.samples = samples
        self.queryError = queryError
        self.bypassExternalIDFilter = bypassExternalIDFilter
    }

    func requestAuthorization(read: Set<HealthQuantityKey>, write: Set<HealthQuantityKey>) async throws {}
    func writeAuthorizationStatus(for identifier: HealthQuantityKey) -> HealthWriteAuthorizationStatus { .sharingAuthorized }
    func readVisibility(for identifiers: Set<HealthQuantityKey>) async throws -> HealthReadVisibility { .unverifiable }
    func existingSamples(type: HealthQuantityKey, unit: ControlledUnit, start: Date, end: Date) async throws -> [HealthSampleSummary] { [] }
    func save(_ samples: [HealthSampleDraft]) async throws { XCTFail("Verification must never write HealthKit") }
    func samplesAuthoredByThisApp(externalIDs: Set<String>, unitsByType: [HealthQuantityKey: ControlledUnit]) async throws -> [HealthSampleSummary] {
        if let queryError { throw queryError }
        if bypassExternalIDFilter { return samples }
        return samples.filter { sample in
            guard let externalID = sample.externalID else { return false }
            return externalIDs.contains(externalID)
        }
    }
}
