import XCTest
@testable import BioMIRBackfill

final class SourceFingerprintTests: XCTestCase {
    func testSHA256MatchesKnownVector() {
        let digest = SourceFingerprint.sha256(data: Data("abc".utf8))
        XCTAssertEqual(
            digest,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testDocumentLoadFingerprintsExactOriginalBytes() throws {
        let data = Data([0xEF, 0xBB, 0xBF] + Array("Date,Sodium (mg)\n2025-01-01,100\n".utf8))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try SourceDocumentService().load(from: url)

        XCTAssertEqual(loaded.data, data)
        XCTAssertEqual(loaded.sha256, SourceFingerprint.sha256(data: data))
        XCTAssertEqual(loaded.filename, url.lastPathComponent)
    }
}
