import Foundation

@main
struct Task8Harness {
    @MainActor
    static func main() async throws {
        try await testGuardedTransitions()
        try await testPreflightChangeBlocksWrite()
        try await testSuccessfulFlow()
        print("TASK 8 PORTABLE WORKFLOW: PASS")
    }

    @MainActor
    static func testGuardedTransitions() async throws {
        let gateway = HarnessGateway()
        let ctx = try makeContext(gateway: gateway)
        await ctx.vm.selectSource(url: ctx.sourceURL)
        precondition(ctx.vm.stage == .review)
        precondition(!ctx.vm.canImport)
        await ctx.vm.performImport()
        precondition(gateway.savedDrafts.isEmpty)
        ctx.vm.continueToPreflight()
        await ctx.vm.runPreflight()
        precondition(ctx.vm.preflightSummary?.visibilityWarning == PreflightEngine.unverifiableVisibilityWarning)
        precondition(!ctx.vm.canImport)
        ctx.vm.setPreflightReviewed(true)
        precondition(ctx.vm.canImport)
    }

    @MainActor
    static func testPreflightChangeBlocksWrite() async throws {
        let gateway = HarnessGateway()
        let ctx = try makeContext(gateway: gateway)
        await ctx.vm.selectSource(url: ctx.sourceURL)
        ctx.vm.continueToPreflight()
        await ctx.vm.runPreflight()
        ctx.vm.setPreflightReviewed(true)
        gateway.returnExisting = true
        await ctx.vm.performImport()
        precondition(gateway.savedDrafts.isEmpty)
        precondition(ctx.vm.stage == .preflight)
        precondition(ctx.vm.preflightReviewed == false)
        precondition(ctx.vm.preflightSummary?.existingCount == 1)
    }

    @MainActor
    static func testSuccessfulFlow() async throws {
        let gateway = HarnessGateway()
        let ctx = try makeContext(gateway: gateway)
        await ctx.vm.selectSource(url: ctx.sourceURL)
        ctx.vm.continueToPreflight()
        await ctx.vm.runPreflight()
        ctx.vm.setPreflightReviewed(true)
        await ctx.vm.performImport()
        precondition(ctx.vm.stage == .results)
        precondition(gateway.savedDrafts.count == 1)
        precondition(ctx.vm.resultSummary?.importedCount == 1)
        precondition(ctx.vm.resultSummary?.verifiedCount == 1)
        precondition(ctx.vm.resultSummary?.isVerifiedComplete == true)
        guard let audit = ctx.vm.auditBundleURL else { preconditionFailure("missing audit bundle") }
        precondition(FileManager.default.fileExists(atPath: audit.appendingPathComponent("SHA256SUMS.json").path))
    }

    @MainActor
    static func makeContext(gateway: HarnessGateway) throws -> (vm: ImportViewModel, sourceURL: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Task8Harness-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("history.csv")
        try Data("Date,Sodium (mg),Net Carbs (g)\n2025-01-01,1500,20\n".utf8).write(to: source)
        let zone = TimeZone(identifier: "America/New_York")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let ledger = try AuditLedger(storageURL: root.appendingPathComponent("ledger.jsonl"))
        let journal = try ImportJournal(storageURL: root.appendingPathComponent("journal.jsonl"))
        let vm = ImportViewModel(
            gateway: gateway,
            auditLedger: ledger,
            journal: journal,
            auditExporter: AuditExporter(baseDirectory: root),
            sourceTimeZone: zone,
            calendar: calendar,
            environmentProvider: {
                ImportManifestEnvironment(appVersion: "0.1", appBuild: "8", osVersion: "portable", generatedAt: Date(timeIntervalSince1970: 1_800_000_000))
            }
        )
        return (vm, source)
    }
}

final class HarnessGateway: HealthStoreGateway, @unchecked Sendable {
    var isHealthDataAvailable = true
    var statuses: [HealthQuantityKey: HealthWriteAuthorizationStatus] = [:]
    var savedDrafts: [HealthSampleDraft] = []
    var returnExisting = false

    func requestAuthorization(read: Set<HealthQuantityKey>, write: Set<HealthQuantityKey>) async throws {
        for id in write { statuses[id] = .sharingAuthorized }
    }
    func writeAuthorizationStatus(for identifier: HealthQuantityKey) -> HealthWriteAuthorizationStatus { statuses[identifier] ?? .notDetermined }
    func readVisibility(for identifiers: Set<HealthQuantityKey>) async throws -> HealthReadVisibility { .unverifiable }
    func existingSamples(type: HealthQuantityKey, unit: ControlledUnit, start: Date, end: Date) async throws -> [HealthSampleSummary] {
        guard returnExisting else { return [] }
        return [HealthSampleSummary(uuid: UUID(), typeIdentifier: type, value: 1, unit: unit, startDate: start, endDate: end, sourceBundleIdentifier: "other", externalID: nil, wasUserEntered: nil, stringMetadata: [:])]
    }
    func save(_ samples: [HealthSampleDraft]) async throws { savedDrafts.append(contentsOf: samples) }
    func samplesAuthoredByThisApp(externalIDs: Set<String>, unitsByType: [HealthQuantityKey: ControlledUnit]) async throws -> [HealthSampleSummary] {
        savedDrafts.compactMap { d in
            guard let id = d.externalID, externalIDs.contains(id) else { return nil }
            return HealthSampleSummary(uuid: UUID(), typeIdentifier: d.typeIdentifier, value: d.value, unit: d.unit, startDate: d.startDate, endDate: d.endDate, sourceBundleIdentifier: "co.biomir.backfill", externalID: id, wasUserEntered: d.wasUserEntered, stringMetadata: d.stringMetadata)
        }
    }
}
