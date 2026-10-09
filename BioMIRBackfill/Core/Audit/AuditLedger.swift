import Foundation

enum AuditDisposition: String, Codable, CaseIterable, Hashable, Sendable {
    case imported = "IMPORTED"
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

struct AuditRecord: Codable, Equatable, Sendable {
    let eventID: UUID
    let runID: UUID
    let subjectKey: String
    let externalID: String?
    let rowNumber: Int
    let sourceColumn: String
    let sourceDate: String
    let healthIdentifier: String
    let disposition: AuditDisposition
    let batchID: UUID?
    let timestamp: Date
    let detail: String?
}

struct AuditSummary: Equatable, Sendable {
    let runID: UUID
    let totalSubjects: Int
    let counts: [AuditDisposition: Int]

    func count(_ disposition: AuditDisposition) -> Int {
        counts[disposition, default: 0]
    }
}

actor AuditLedger {
    private let storageURL: URL?
    private var records: [AuditRecord]

    init(storageURL: URL?) throws {
        self.storageURL = storageURL
        self.records = try Self.loadRecords(from: storageURL)
    }

    func append(_ record: AuditRecord) throws {
        records.append(record)
        do {
            try Self.appendLine(record, to: storageURL)
        } catch {
            records.removeLast()
            throw error
        }
    }

    func records(for runID: UUID) -> [AuditRecord] {
        records.filter { $0.runID == runID }
    }

    func summary(for runID: UUID) -> AuditSummary {
        let runRecords = records.filter { $0.runID == runID }
        var latest: [String: AuditRecord] = [:]
        for record in runRecords {
            if let existing = latest[record.subjectKey] {
                if record.timestamp > existing.timestamp ||
                    (record.timestamp == existing.timestamp && record.eventID.uuidString > existing.eventID.uuidString) {
                    latest[record.subjectKey] = record
                }
            } else {
                latest[record.subjectKey] = record
            }
        }

        var counts: [AuditDisposition: Int] = [:]
        for record in latest.values {
            counts[record.disposition, default: 0] += 1
        }
        return AuditSummary(runID: runID, totalSubjects: latest.count, counts: counts)
    }

    private static func loadRecords(from url: URL?) throws -> [AuditRecord] {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try data.split(separator: 0x0A).filter { !$0.isEmpty }.map { line in
            try decoder.decode(AuditRecord.self, from: Data(line))
        }
    }

    private static func appendLine(_ record: AuditRecord, to url: URL?) throws {
        guard let url else { return }
        try ensureParentDirectory(for: url)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(record)
        data.append(0x0A)
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private static func ensureParentDirectory(for url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
}
