import Foundation
import XCTest
@testable import BioMIRBackfill

final class HealthStoreGatewayTests: XCTestCase {
    func testFakeGatewayCanModelWriteAuthorizationSeparatelyFromReadVisibility() async throws {
        let fake = FakeHealthStoreGateway(
            writeStatuses: [.dietarySodium: .sharingAuthorized],
            readVisibilityValue: .unverifiable
        )

        try await fake.requestAuthorization(
            read: [.dietarySodium],
            write: [.dietarySodium]
        )

        XCTAssertEqual(fake.writeAuthorizationStatus(for: .dietarySodium), .sharingAuthorized)
        let visibility = try await fake.readVisibility(for: [.dietarySodium])
        XCTAssertEqual(visibility, .unverifiable)
    }

    func testFakeGatewayReturnsVisibleExistingSamplesWithoutAnyMutation() async throws {
        let sample = HealthSampleSummary(
            uuid: UUID(),
            typeIdentifier: .dietarySodium,
            value: 1800,
            unit: .milligram,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_086_400),
            sourceBundleIdentifier: "com.example.source",
            externalID: nil, wasUserEntered: nil, stringMetadata: [:]
        )
        let fake = FakeHealthStoreGateway(existing: [.dietarySodium: [sample]])

        let result = try await fake.existingSamples(
            type: .dietarySodium,
            unit: .milligram,
            start: sample.startDate,
            end: sample.endDate
        )

        XCTAssertEqual(result, [sample])
        XCTAssertTrue(fake.savedDrafts.isEmpty)
    }
}

private final class FakeHealthStoreGateway: HealthStoreGateway, @unchecked Sendable {
    var isHealthDataAvailable = true
    var writeStatuses: [HealthQuantityKey: HealthWriteAuthorizationStatus]
    var readVisibilityValue: HealthReadVisibility
    var existing: [HealthQuantityKey: [HealthSampleSummary]]
    var savedDrafts: [HealthSampleDraft] = []

    init(
        writeStatuses: [HealthQuantityKey: HealthWriteAuthorizationStatus] = [:],
        readVisibilityValue: HealthReadVisibility = .unverifiable,
        existing: [HealthQuantityKey: [HealthSampleSummary]] = [:]
    ) {
        self.writeStatuses = writeStatuses
        self.readVisibilityValue = readVisibilityValue
        self.existing = existing
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
        existing[type] ?? []
    }

    func save(_ samples: [HealthSampleDraft]) async throws {
        savedDrafts.append(contentsOf: samples)
    }

    func samplesAuthoredByThisApp(
        externalIDs: Set<String>,
        unitsByType: [HealthQuantityKey: ControlledUnit]
    ) async throws -> [HealthSampleSummary] {
        existing.values.flatMap { $0 }.filter { sample in
            guard let externalID = sample.externalID else { return false }
            return externalIDs.contains(externalID)
        }
    }
}
