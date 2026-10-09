import Foundation

enum PreflightDisposition: String, Equatable, Sendable {
    case eligible = "ELIGIBLE"
    case skippedExisting = "SKIPPED_EXISTING"
    case skippedMissing = "SKIPPED_MISSING"
    case skippedZeroPolicy = "SKIPPED_ZERO_POLICY"
    case unsupported = "UNSUPPORTED"
    case rejectedRange = "REJECTED_RANGE"
    case rejectedUnit = "REJECTED_UNIT"
    case rejectedMapping = "REJECTED_MAPPING"
    case authorizationBlocked = "AUTHORIZATION_BLOCKED"
    case writeFailed = "WRITE_FAILED"
    case verificationFailed = "VERIFICATION_FAILED"
}

struct PreflightDispositionRecord: Equatable, Sendable {
    let candidate: MappedCandidate
    let disposition: PreflightDisposition
    let visibleExistingSampleCount: Int
}

struct PreflightReport: Equatable, Sendable {
    let manifest: ImportManifest
    let dispositions: [PreflightDispositionRecord]
    let unsupportedFields: [UnsupportedField]
    let readVisibility: HealthReadVisibility
    let visibilityWarning: String?

    var eligible: [MappedCandidate] {
        dispositions.compactMap { record in
            record.disposition == .eligible ? record.candidate : nil
        }
    }

    func count(_ disposition: PreflightDisposition) -> Int {
        dispositions.lazy.filter { $0.disposition == disposition }.count
    }
}

struct ImportedSampleExpectation: Equatable, Sendable {
    let rowNumber: Int
    let sourceColumn: String
    let sourceDate: String
    let batchID: UUID
    let draft: HealthSampleDraft
}

struct ImportResult: Equatable, Sendable {
    let runID: UUID
    let importedCount: Int
    let skippedExistingCount: Int
    let skippedMissingCount: Int
    let skippedZeroPolicyCount: Int
    let authorizationBlockedCount: Int
    let externalIDs: [String]
    let verificationExpectations: [ImportedSampleExpectation]
}

enum SourceIntegrityError: Error, Equatable, CustomStringConvertible {
    case sourceChanged(reviewedSHA256: String, currentSHA256: String)

    var description: String {
        switch self {
        case .sourceChanged(let reviewed, let current):
            return "Source file changed after preflight review (reviewed SHA-256: \(reviewed), current SHA-256: \(current))."
        }
    }
}
