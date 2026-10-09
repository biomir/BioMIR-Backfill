import XCTest
@testable import BioMIRBackfill

final class ArchitectureBoundaryTests: XCTestCase {
    func testCompanionTargetDoesNotImportBioMIRAnalyticalModules() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent() // BioMIRBackfillTests
            .deletingLastPathComponent() // repository root
        let sourceRoot = repoRoot.appendingPathComponent("BioMIRBackfill", isDirectory: true)

        let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let forbidden = [
            "import BioMIR",
            "IndexEngine",
            "HealthKitManager",
            "HistoryStore.shared"
        ]

        var violations: [String] = []
        while let file = enumerator?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden where source.contains(token) {
                violations.append("\(file.lastPathComponent): \(token)")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "BioMIR Backfill must remain independent of BioMIR analytics: \(violations.joined(separator: ", "))"
        )
    }

    func testInitialImportStagesAreExactlyFourGuardedStages() {
        XCTAssertEqual(
            ImportStage.allCases,
            [.selectSource, .review, .preflight, .results]
        )
    }
}
