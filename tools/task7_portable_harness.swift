import Foundation

@main
struct Task7PortableHarness {
    static func main() async throws {
        let batchID = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
        let externalID = "12345678-1234-8123-8123-123456789abc"
        let draft = HealthSampleDraft(
            typeIdentifier: .dietarySodium, value: 1500, unit: .milligram,
            startDate: Date(timeIntervalSince1970: 1_735_689_600),
            endDate: Date(timeIntervalSince1970: 1_735_776_000), externalID: externalID,
            wasUserEntered: true,
            stringMetadata: [ProvenanceService.MetadataKey.batchUUID: batchID.uuidString.lowercased()]
        )
        let expectation = ImportedSampleExpectation(
            rowNumber: 2, sourceColumn: "Sodium (mg)", sourceDate: "2025-01-01", batchID: batchID, draft: draft
        )
        let result = ImportResult(
            runID: UUID(), importedCount: 1, skippedExistingCount: 0, skippedMissingCount: 0,
            skippedZeroPolicyCount: 0, authorizationBlockedCount: 0, externalIDs: [externalID],
            verificationExpectations: [expectation]
        )
        let good = PortableVerificationGateway(samples: [HealthSampleSummary(
            uuid: UUID(), typeIdentifier: .dietarySodium, value: 1500, unit: .milligram,
            startDate: draft.startDate, endDate: draft.endDate,
            sourceBundleIdentifier: "co.biomir.backfill", externalID: externalID,
            wasUserEntered: true, stringMetadata: draft.stringMetadata
        )])
        let report = await VerificationEngine().verify(importResult: result, gateway: good)
        guard report.isVerifiedComplete, report.verifiedCount == 1 else { fatalError("exact match did not verify") }

        let missing = await VerificationEngine().verify(
            importResult: result, gateway: PortableVerificationGateway(samples: [])
        )
        guard !missing.isVerifiedComplete, missing.items.first?.failureReasons == [.missingSample] else {
            fatalError("missing sample did not fail verification")
        }

        print("TASK 7 PORTABLE VERIFICATION: PASS")
    }
}

private final class PortableVerificationGateway: HealthStoreGateway, @unchecked Sendable {
    var isHealthDataAvailable = true
    let samples: [HealthSampleSummary]
    init(samples: [HealthSampleSummary]) { self.samples = samples }
    func requestAuthorization(read: Set<HealthQuantityKey>, write: Set<HealthQuantityKey>) async throws {}
    func writeAuthorizationStatus(for identifier: HealthQuantityKey) -> HealthWriteAuthorizationStatus { .sharingAuthorized }
    func readVisibility(for identifiers: Set<HealthQuantityKey>) async throws -> HealthReadVisibility { .unverifiable }
    func existingSamples(type: HealthQuantityKey, unit: ControlledUnit, start: Date, end: Date) async throws -> [HealthSampleSummary] { [] }
    func save(_ samples: [HealthSampleDraft]) async throws { fatalError("verification must not write") }
    func samplesAuthoredByThisApp(externalIDs: Set<String>, unitsByType: [HealthQuantityKey: ControlledUnit]) async throws -> [HealthSampleSummary] {
        samples.filter { $0.externalID.map(externalIDs.contains) ?? false }
    }
}
