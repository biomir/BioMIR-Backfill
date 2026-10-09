import Foundation

enum HealthWriteAuthorizationStatus: String, Equatable, Sendable {
    case notDetermined
    case sharingDenied
    case sharingAuthorized
}

enum HealthReadVisibility: Equatable, Sendable {
    /// HealthKit intentionally does not distinguish full read access from denied read access.
    /// On the current iOS 26 SDK, limited-history introspection is not available either.
    case unverifiable

    /// Reserved for the iOS 27+ limited-history API once BioMIR Backfill adopts that SDK.
    case limited(earliestByIdentifier: [HealthQuantityKey: Date])
}

struct HealthAuthorizationState: Equatable, Sendable {
    let healthDataAvailable: Bool
    let writeStatusByIdentifier: [HealthQuantityKey: HealthWriteAuthorizationStatus]
    let readVisibility: HealthReadVisibility

    var allRequestedWritesAuthorized: Bool {
        !writeStatusByIdentifier.isEmpty &&
        writeStatusByIdentifier.values.allSatisfy { $0 == .sharingAuthorized }
    }
}
