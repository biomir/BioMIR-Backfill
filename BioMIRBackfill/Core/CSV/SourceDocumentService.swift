import Foundation

struct LoadedSourceDocument: Sendable {
    let url: URL
    let filename: String
    let data: Data
    let sha256: String
}

struct SourceDocumentService {
    func load(from url: URL) throws -> LoadedSourceDocument {
        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return LoadedSourceDocument(
            url: url,
            filename: url.lastPathComponent,
            data: data,
            sha256: SourceFingerprint.sha256(data: data)
        )
    }
}
