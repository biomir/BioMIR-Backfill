import Foundation

struct ProvenanceContext: Equatable, Sendable {
    let batchID: UUID
    let candidate: MappedCandidate
    let manifest: ImportManifest
}

enum ProvenanceService {
    static let schemaVersion = "provenance-v0.1"
    static let historicalImportClassification = "historical-user-controlled-import"

    enum MetadataKey {
        static let batchUUID = "co.biomir.backfill.batch_uuid"
        static let schemaVersion = "co.biomir.backfill.provenance_schema"
        static let mappingVersion = "co.biomir.backfill.mapping_version"
        static let parserVersion = "co.biomir.backfill.parser_version"
        static let sourceCalendarDate = "co.biomir.backfill.source_calendar_date"
        static let sourceField = "co.biomir.backfill.source_field"
        static let sourceUnit = "co.biomir.backfill.source_unit"
        static let transformationID = "co.biomir.backfill.transformation_id"
        static let transformationVersion = "co.biomir.backfill.transformation_version"
        static let sourceSHA256 = "co.biomir.backfill.source_sha256"
        static let sourceSchemaSHA256 = "co.biomir.backfill.source_schema_sha256"
        static let sourceFilename = "co.biomir.backfill.source_filename"
        static let sourceRow = "co.biomir.backfill.source_row"
        static let classification = "co.biomir.backfill.classification"
        static let timeAnchorPolicy = "co.biomir.backfill.time_anchor_policy"
    }

    static func externalUUID(for candidate: MappedCandidate, manifest: ImportManifest) -> String {
        let material = [
            schemaVersion,
            manifest.sourceSHA256,
            String(candidate.rowNumber),
            candidate.healthIdentifier.rawValue,
            isoDate(candidate.sourceDate),
            manifest.mappingVersion
        ].joined(separator: "\u{001F}")

        let digest = StableSHA256.digest(Array(material.utf8))
        var bytes = Array(digest.prefix(16))
        // RFC 9562 variant + UUIDv8/custom layout for a BioMIR-controlled SHA-256 identity.
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let hex = bytes.map { String(format: "%02x", $0) }
        return "\(hex[0...3].joined())-\(hex[4...5].joined())-\(hex[6...7].joined())-\(hex[8...9].joined())-\(hex[10...15].joined())"
    }

    static func stringMetadata(for context: ProvenanceContext) -> [String: String] {
        [
            MetadataKey.batchUUID: context.batchID.uuidString.lowercased(),
            MetadataKey.schemaVersion: schemaVersion,
            MetadataKey.mappingVersion: context.manifest.mappingVersion,
            MetadataKey.parserVersion: context.manifest.parserVersion,
            MetadataKey.sourceCalendarDate: isoDate(context.candidate.sourceDate),
            MetadataKey.sourceField: context.candidate.sourceColumn,
            MetadataKey.sourceUnit: context.candidate.originalUnit,
            MetadataKey.transformationID: context.candidate.transformationID,
            MetadataKey.transformationVersion: context.candidate.transformationVersion,
            MetadataKey.sourceSHA256: context.manifest.sourceSHA256,
            MetadataKey.sourceSchemaSHA256: context.manifest.schemaSHA256,
            MetadataKey.sourceFilename: context.manifest.sourceFilename,
            MetadataKey.sourceRow: String(context.candidate.rowNumber),
            MetadataKey.classification: historicalImportClassification,
            MetadataKey.timeAnchorPolicy: "daily-aggregate-noon-v1"
        ]
    }

    static func isoDate(_ components: DateComponents) -> String {
        guard let year = components.year, let month = components.month, let day = components.day else {
            return "invalid-date"
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

private enum StableSHA256 {
    private static let initial: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]

    private static let constants: [UInt32] = [
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
    ]

    static func digest(_ input: [UInt8]) -> [UInt8] {
        var message = input
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        message.append(contentsOf: withUnsafeBytes(of: bitLength.bigEndian, Array.init))

        var hash = initial
        var words = [UInt32](repeating: 0, count: 64)

        for offset in stride(from: 0, to: message.count, by: 64) {
            for i in 0..<16 {
                let j = offset + i * 4
                words[i] = UInt32(message[j]) << 24 |
                    UInt32(message[j + 1]) << 16 |
                    UInt32(message[j + 2]) << 8 |
                    UInt32(message[j + 3])
            }
            for i in 16..<64 {
                let s0 = rotateRight(words[i - 15], by: 7) ^ rotateRight(words[i - 15], by: 18) ^ (words[i - 15] >> 3)
                let s1 = rotateRight(words[i - 2], by: 17) ^ rotateRight(words[i - 2], by: 19) ^ (words[i - 2] >> 10)
                words[i] = words[i - 16] &+ s0 &+ words[i - 7] &+ s1
            }

            var a = hash[0], b = hash[1], c = hash[2], d = hash[3]
            var e = hash[4], f = hash[5], g = hash[6], h = hash[7]

            for i in 0..<64 {
                let s1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
                let choice = (e & f) ^ ((~e) & g)
                let temp1 = h &+ s1 &+ choice &+ constants[i] &+ words[i]
                let s0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ majority
                h = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }

            hash[0] = hash[0] &+ a; hash[1] = hash[1] &+ b
            hash[2] = hash[2] &+ c; hash[3] = hash[3] &+ d
            hash[4] = hash[4] &+ e; hash[5] = hash[5] &+ f
            hash[6] = hash[6] &+ g; hash[7] = hash[7] &+ h
        }

        return hash.flatMap { word in
            let be = word.bigEndian
            return withUnsafeBytes(of: be, Array.init)
        }
    }

    private static func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}
