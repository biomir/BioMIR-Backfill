import Foundation

struct HealthSampleSummary: Equatable, Sendable {
    let uuid: UUID
    let typeIdentifier: HealthQuantityKey
    let value: Double
    let unit: ControlledUnit
    let startDate: Date
    let endDate: Date
    let sourceBundleIdentifier: String
    let externalID: String?
    let wasUserEntered: Bool?
    let stringMetadata: [String: String]
}

struct HealthSampleDraft: Equatable, Sendable {
    let typeIdentifier: HealthQuantityKey
    let value: Double
    let unit: ControlledUnit
    let startDate: Date
    let endDate: Date
    let externalID: String?
    let wasUserEntered: Bool
    let stringMetadata: [String: String]
}

struct HistoricalSampleDeletionRequest: Equatable, Sendable {
    let types: Set<HealthQuantityKey>
    let mappingVersions: Set<String>
    let classification: String
    let startDate: Date
    let endDate: Date
}

enum HistoricalNutritionNoonRepairPolicy {
    static let mappingVersions: Set<String> = [
        "nutrition-v0.1",
        "carbmanager-total-carb-v1"
    ]
    static let classification = "historical-user-controlled-import"
    static let targetTypes = Set(HealthQuantityKey.allCases)

    static func deletionRequest(calendar: Calendar) throws -> HistoricalSampleDeletionRequest {
        let first = try CalendarDayInterval.dayInterval(
            for: DateComponents(year: 2021, month: 3, day: 11),
            calendar: calendar
        )
        let last = try CalendarDayInterval.dayInterval(
            for: DateComponents(year: 2025, month: 1, day: 8),
            calendar: calendar
        )
        return HistoricalSampleDeletionRequest(
            types: targetTypes,
            mappingVersions: mappingVersions,
            classification: classification,
            startDate: first.start,
            endDate: last.end
        )
    }
}

enum HistoricalSampleDeletionError: Error, Equatable {
    case unsupportedByGateway
}

protocol HealthStoreGateway: Sendable {
    var isHealthDataAvailable: Bool { get }

    func requestAuthorization(
        read: Set<HealthQuantityKey>,
        write: Set<HealthQuantityKey>
    ) async throws

    func writeAuthorizationStatus(
        for identifier: HealthQuantityKey
    ) -> HealthWriteAuthorizationStatus

    func readVisibility(
        for identifiers: Set<HealthQuantityKey>
    ) async throws -> HealthReadVisibility

    func existingSamples(
        type: HealthQuantityKey,
        unit: ControlledUnit,
        start: Date,
        end: Date
    ) async throws -> [HealthSampleSummary]

    func save(_ samples: [HealthSampleDraft]) async throws

    func samplesAuthoredByThisApp(
        externalIDs: Set<String>,
        unitsByType: [HealthQuantityKey: ControlledUnit]
    ) async throws -> [HealthSampleSummary]

    func deleteAppAuthoredSamples(
        matching request: HistoricalSampleDeletionRequest
    ) async throws -> Int
}

extension HealthStoreGateway {
    func deleteAppAuthoredSamples(
        matching request: HistoricalSampleDeletionRequest
    ) async throws -> Int {
        throw HistoricalSampleDeletionError.unsupportedByGateway
    }
}
