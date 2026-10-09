import Foundation

enum BatchWriteStatus: String, Codable, Equatable, Sendable {
    case started
    case succeeded
    case failed
}

struct ImportJournalEvent: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case started, succeeded, failed }

    let kind: Kind
    let eventID: UUID
    let runID: UUID
    let batchID: UUID
    let sourceSHA256: String?
    let rangeStart: Int?
    let rangeEndExclusive: Int?
    let plannedExternalIDs: [String]?
    let timestamp: Date
    let errorDescription: String?

    static func started(
        eventID: UUID, runID: UUID, batchID: UUID, sourceSHA256: String,
        rangeStart: Int, rangeEndExclusive: Int, plannedExternalIDs: [String], timestamp: Date
    ) -> Self {
        Self(kind: .started, eventID: eventID, runID: runID, batchID: batchID,
             sourceSHA256: sourceSHA256, rangeStart: rangeStart, rangeEndExclusive: rangeEndExclusive,
             plannedExternalIDs: plannedExternalIDs, timestamp: timestamp, errorDescription: nil)
    }

    static func succeeded(eventID: UUID, runID: UUID, batchID: UUID, timestamp: Date) -> Self {
        Self(kind: .succeeded, eventID: eventID, runID: runID, batchID: batchID,
             sourceSHA256: nil, rangeStart: nil, rangeEndExclusive: nil,
             plannedExternalIDs: nil, timestamp: timestamp, errorDescription: nil)
    }

    static func failed(
        eventID: UUID, runID: UUID, batchID: UUID, timestamp: Date, errorDescription: String
    ) -> Self {
        Self(kind: .failed, eventID: eventID, runID: runID, batchID: batchID,
             sourceSHA256: nil, rangeStart: nil, rangeEndExclusive: nil,
             plannedExternalIDs: nil, timestamp: timestamp, errorDescription: errorDescription)
    }
}

struct ImportBatchState: Equatable, Sendable {
    let runID: UUID
    let batchID: UUID
    let sourceSHA256: String
    let rangeStart: Int
    let rangeEndExclusive: Int
    let plannedExternalIDs: [String]
    let writeStatus: BatchWriteStatus
    let startedAt: Date
    let finishedAt: Date?
    let errorDescription: String?

    var plannedCount: Int { plannedExternalIDs.count }
}

actor ImportJournal {
    private let storageURL: URL?
    private var events: [ImportJournalEvent]

    init(storageURL: URL?) throws {
        self.storageURL = storageURL
        self.events = try Self.loadEvents(from: storageURL)
    }

    func append(_ event: ImportJournalEvent) throws {
        events.append(event)
        do {
            try Self.appendLine(event, to: storageURL)
        } catch {
            events.removeLast()
            throw error
        }
    }

    func batchStates() -> [ImportBatchState] {
        var starts: [UUID: ImportJournalEvent] = [:]
        var terminals: [UUID: ImportJournalEvent] = [:]

        for event in events {
            switch event.kind {
            case .started:
                if let current = starts[event.batchID] {
                    if event.timestamp < current.timestamp { starts[event.batchID] = event }
                } else {
                    starts[event.batchID] = event
                }
            case .succeeded, .failed:
                if let current = terminals[event.batchID] {
                    if event.timestamp > current.timestamp { terminals[event.batchID] = event }
                } else {
                    terminals[event.batchID] = event
                }
            }
        }

        return starts.values.compactMap { start in
            guard let sourceSHA256 = start.sourceSHA256,
                  let rangeStart = start.rangeStart,
                  let rangeEndExclusive = start.rangeEndExclusive,
                  let ids = start.plannedExternalIDs else { return nil }
            let terminal = terminals[start.batchID]
            let status: BatchWriteStatus
            if terminal?.kind == .succeeded { status = .succeeded }
            else if terminal?.kind == .failed { status = .failed }
            else { status = .started }
            return ImportBatchState(
                runID: start.runID, batchID: start.batchID, sourceSHA256: sourceSHA256,
                rangeStart: rangeStart, rangeEndExclusive: rangeEndExclusive,
                plannedExternalIDs: ids, writeStatus: status, startedAt: start.timestamp,
                finishedAt: terminal?.timestamp, errorDescription: terminal?.errorDescription
            )
        }.sorted {
            if $0.startedAt == $1.startedAt { return $0.rangeStart < $1.rangeStart }
            return $0.startedAt < $1.startedAt
        }
    }

    private static func loadEvents(from url: URL?) throws -> [ImportJournalEvent] {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try data.split(separator: 0x0A).filter { !$0.isEmpty }.map { line in
            try decoder.decode(ImportJournalEvent.self, from: Data(line))
        }
    }

    private static func appendLine(_ event: ImportJournalEvent, to url: URL?) throws {
        guard let url else { return }
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(event)
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
}
