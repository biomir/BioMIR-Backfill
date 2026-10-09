import CryptoKit
import Foundation

enum SourceFingerprint {
    static func sha256(data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func sha256(url: URL) throws -> String {
        sha256(data: try Data(contentsOf: url, options: [.mappedIfSafe]))
    }
}
