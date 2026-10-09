import Foundation

enum AuditExporterError: Error, Equatable {
    case destinationAlreadyExists(URL)
}

private struct AuditManifestSnapshot: Codable {
    let sourceFilename: String
    let sourceSHA256: String
    let sourceByteCount: Int
    let rowCount: Int
    let encoding: String
    let sourceTimeZoneIdentifier: String
    let sourceDateStart: String?
    let sourceDateEnd: String?
    let headers: [String]
    let schemaSHA256: String
    let parserVersion: String
    let mappingVersion: String
    let appVersion: String
    let appBuild: String
    let osVersion: String
    let generatedAt: Date

    init(_ manifest: ImportManifest) {
        sourceFilename = manifest.sourceFilename
        sourceSHA256 = manifest.sourceSHA256
        sourceByteCount = manifest.sourceByteCount
        rowCount = manifest.rowCount
        encoding = manifest.encoding
        sourceTimeZoneIdentifier = manifest.sourceTimeZoneIdentifier
        sourceDateStart = manifest.sourceDateStart
        sourceDateEnd = manifest.sourceDateEnd
        headers = manifest.headers
        schemaSHA256 = manifest.schemaSHA256
        parserVersion = manifest.parserVersion
        mappingVersion = manifest.mappingVersion
        appVersion = manifest.appVersion
        appBuild = manifest.appBuild
        osVersion = manifest.osVersion
        generatedAt = manifest.generatedAt
    }
}

struct AuditExporter {
    let baseDirectory: URL

    init(baseDirectory: URL = FileManager.default.temporaryDirectory) {
        self.baseDirectory = baseDirectory
    }

    func export(
        manifest: ImportManifest,
        ledger: AuditLedger,
        verification: VerificationReport
    ) async throws -> URL {
        let bundleName = "BioMIR_Backfill_Audit_\(verification.runID.uuidString.lowercased())"
        let bundleURL = baseDirectory.appendingPathComponent(bundleName, isDirectory: true)

        guard !FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw AuditExporterError.destinationAlreadyExists(bundleURL)
        }

        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

            let manifestData = try encoder.encode(AuditManifestSnapshot(manifest))
            try manifestData.write(to: bundleURL.appendingPathComponent("manifest.json"), options: .atomic)

            let mappingData = Data((manifest.mappingVersion + "\n").utf8)
            try mappingData.write(to: bundleURL.appendingPathComponent("mapping-version.txt"), options: .atomic)

            let verificationData = try encoder.encode(verification)
            try verificationData.write(to: bundleURL.appendingPathComponent("verification.json"), options: .atomic)

            let records = await ledger.records(for: verification.runID)
            let ledgerData = try encodeLedgerJSONL(records)
            try ledgerData.write(to: bundleURL.appendingPathComponent("audit-ledger.jsonl"), options: .atomic)

            let artifactNames = [
                "manifest.json",
                "mapping-version.txt",
                "audit-ledger.jsonl",
                "verification.json"
            ]
            var hashes: [String: String] = [:]
            for name in artifactNames {
                let data = try Data(contentsOf: bundleURL.appendingPathComponent(name), options: [.mappedIfSafe])
                hashes[name] = SourceFingerprint.sha256(data: data)
            }

            let hashesData = try encoder.encode(hashes)
            try hashesData.write(to: bundleURL.appendingPathComponent("SHA256SUMS.json"), options: .atomic)
            return bundleURL
        } catch {
            try? FileManager.default.removeItem(at: bundleURL)
            throw error
        }
    }

    private func encodeLedgerJSONL(_ records: [AuditRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        var data = Data()
        for record in records {
            data.append(try encoder.encode(record))
            data.append(0x0A)
        }
        return data
    }
}
