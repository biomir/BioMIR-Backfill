import Foundation

struct ImportManifestEnvironment: Equatable, Sendable {
    let appVersion: String
    let appBuild: String
    let osVersion: String
    let generatedAt: Date
}

struct ImportManifest: Equatable, Sendable {
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
}

enum SourceIntegrityGate {
    static func assertUnchanged(reviewedManifest: ImportManifest, currentSHA256: String) throws {
        guard reviewedManifest.sourceSHA256 == currentSHA256 else {
            throw SourceIntegrityError.sourceChanged(
                reviewedSHA256: reviewedManifest.sourceSHA256,
                currentSHA256: currentSHA256
            )
        }
    }
}

#if canImport(CryptoKit)
enum ImportManifestFactory {
    static func make(
        source: LoadedSourceDocument,
        parsedCSV: ParsedCSV,
        mappingResult: MappingResult,
        environment: ImportManifestEnvironment
    ) -> ImportManifest {
        let schemaMaterial = parsedCSV.headers.joined(separator: "\u{001F}")
        let schemaSHA256 = SourceFingerprint.sha256(data: Data(schemaMaterial.utf8))
        let dates = parsedCSV.rows.compactMap { isoDateString($0.sourceDate) }.sorted()

        return ImportManifest(
            sourceFilename: source.filename,
            sourceSHA256: source.sha256,
            sourceByteCount: source.data.count,
            rowCount: parsedCSV.rows.count,
            encoding: parsedCSV.encoding,
            sourceTimeZoneIdentifier: parsedCSV.sourceTimeZoneIdentifier,
            sourceDateStart: dates.first,
            sourceDateEnd: dates.last,
            headers: parsedCSV.headers,
            schemaSHA256: schemaSHA256,
            parserVersion: CSVParser.version,
            mappingVersion: mappingResult.registryVersion,
            appVersion: environment.appVersion,
            appBuild: environment.appBuild,
            osVersion: environment.osVersion,
            generatedAt: environment.generatedAt
        )
    }

    private static func isoDateString(_ components: DateComponents) -> String? {
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
#endif
