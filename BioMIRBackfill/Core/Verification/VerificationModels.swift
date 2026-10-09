import Foundation

enum VerificationStatus: String, Codable, Equatable, Sendable {
    case verified = "VERIFIED"
    case verificationFailed = "VERIFICATION_FAILED"
}

enum VerificationFailureReason: String, Codable, CaseIterable, Equatable, Sendable {
    case missingSample = "MISSING_SAMPLE"
    case duplicateExternalIdentity = "DUPLICATE_EXTERNAL_IDENTITY"
    case typeMismatch = "TYPE_MISMATCH"
    case valueMismatch = "VALUE_MISMATCH"
    case unitMismatch = "UNIT_MISMATCH"
    case startDateMismatch = "START_DATE_MISMATCH"
    case endDateMismatch = "END_DATE_MISMATCH"
    case externalIdentityMismatch = "EXTERNAL_IDENTITY_MISMATCH"
    case userEnteredMismatch = "USER_ENTERED_MISMATCH"
    case provenanceMismatch = "PROVENANCE_MISMATCH"
    case queryFailed = "QUERY_FAILED"
    case auditPersistenceFailed = "AUDIT_PERSISTENCE_FAILED"
}

struct VerificationItemResult: Codable, Equatable, Sendable {
    let externalID: String
    let rowNumber: Int
    let sourceColumn: String
    let sourceDate: String
    let healthIdentifier: String
    let status: VerificationStatus
    let failureReasons: [VerificationFailureReason]
    let observedSampleUUID: String?
}

struct VerificationReport: Codable, Equatable, Sendable {
    let runID: UUID
    let generatedAt: Date
    let expectedCount: Int
    let verifiedCount: Int
    let failedCount: Int
    let isVerifiedComplete: Bool
    let items: [VerificationItemResult]
}
