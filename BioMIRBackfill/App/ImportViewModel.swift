import Foundation

#if canImport(Combine)
import Combine
typealias ImportViewModelObservable = ObservableObject
#else
protocol ImportViewModelObservable: AnyObject {}
#endif

enum ImportStage: String, CaseIterable, Identifiable, Sendable {
    case selectSource
    case review
    case preflight
    case results

    var id: Self { self }

    var title: String {
        switch self {
        case .selectSource: "Select Source"
        case .review: "Review"
        case .preflight: "Preflight"
        case .results: "Results"
        }
    }

    var systemImage: String {
        switch self {
        case .selectSource: "doc.badge.plus"
        case .review: "checklist"
        case .preflight: "heart.text.square"
        case .results: "checkmark.seal"
        }
    }
}

enum ImportWorkflowError: Error, Equatable, LocalizedError {
    case healthDataUnavailable
    case noSourceSelected
    case reviewRequired
    case preflightRequired
    case preflightReviewRequired
    case noEligibleSamples
    case preflightChanged
    case auditPersistenceUnavailable

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "Apple Health is not available on this device."
        case .noSourceSelected:
            return "Choose a compatible historical CSV before continuing."
        case .reviewRequired:
            return "Review the parsed source and controlled mappings before preflight."
        case .preflightRequired:
            return "Run Health preflight before importing."
        case .preflightReviewRequired:
            return "Review and acknowledge the preflight results before importing."
        case .noEligibleSamples:
            return "No historical samples are currently eligible to import."
        case .preflightChanged:
            return "Health preflight changed immediately before import. Review the updated results before continuing."
        case .auditPersistenceUnavailable:
            return "Local audit persistence is unavailable. Import is disabled until the app is restarted successfully."
        }
    }
}

struct SourceReviewSummary: Equatable, Sendable {
    let filename: String
    let fingerprintPrefix: String
    let rowCount: Int
    let dateStart: String?
    let dateEnd: String?
    let supportedMappingCount: Int
    let unsupportedMappingCount: Int
    let mappingVersion: String
    let unsupportedFields: [UnsupportedField]
}

struct HealthPreflightSummary: Equatable, Sendable {
    let eligibleCount: Int
    let existingCount: Int
    let missingCount: Int
    let zeroPolicyCount: Int
    let authorizationBlockedCount: Int
    let unsupportedFieldCount: Int
    let visibilityWarning: String?
}

struct ImportResultSummary: Equatable, Sendable {
    let runID: UUID
    let importedCount: Int
    let skippedExistingCount: Int
    let skippedMissingCount: Int
    let skippedZeroPolicyCount: Int
    let authorizationBlockedCount: Int
    let verifiedCount: Int
    let failedVerificationCount: Int
    let isVerifiedComplete: Bool
}

struct HistoricalNutritionRepairSummary: Equatable, Sendable {
    static let expectedLegacySampleCount = 43_612

    let deletedCount: Int
    let expectedCount: Int

    var matchesExpectedCount: Bool { deletedCount == expectedCount }
}

@MainActor
final class ImportViewModel: ImportViewModelObservable {
    #if canImport(Combine)
    @Published
    #endif
    private(set) var stage: ImportStage = .selectSource

    #if canImport(Combine)
    @Published
    #endif
    private(set) var reviewSummary: SourceReviewSummary?

    #if canImport(Combine)
    @Published
    #endif
    private(set) var preflightSummary: HealthPreflightSummary?

    #if canImport(Combine)
    @Published
    #endif
    private(set) var resultSummary: ImportResultSummary?

    #if canImport(Combine)
    @Published
    #endif
    private(set) var preflightReviewed = false

    #if canImport(Combine)
    @Published
    #endif
    private(set) var auditBundleURL: URL?

    #if canImport(Combine)
    @Published
    #endif
    private(set) var repairSummary: HistoricalNutritionRepairSummary?

    #if canImport(Combine)
    @Published
    #endif
    private(set) var isBusy = false

    #if canImport(Combine)
    @Published
    #endif
    private(set) var errorMessage: String?

    private let gateway: HealthStoreGateway
    private let auditLedger: AuditLedger
    private let journal: ImportJournal
    private let auditExporter: AuditExporter
    private let sourceDocumentService: SourceDocumentService
    private let sourceTimeZone: TimeZone
    private let calendar: Calendar
    private let environmentProvider: () -> ImportManifestEnvironment
    private let persistentAuditAvailable: Bool

    private var sourceURL: URL?
    private var source: LoadedSourceDocument?
    private var parsedCSV: ParsedCSV?
    private var mappingResult: MappingResult?
    private var manifest: ImportManifest?
    private var preflightReport: PreflightReport?
    private var importResult: ImportResult?
    private var verificationReport: VerificationReport?

    init(
        gateway: HealthStoreGateway,
        auditLedger: AuditLedger,
        journal: ImportJournal,
        auditExporter: AuditExporter,
        sourceDocumentService: SourceDocumentService = SourceDocumentService(),
        sourceTimeZone: TimeZone = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent,
        environmentProvider: @escaping () -> ImportManifestEnvironment,
        persistentAuditAvailable: Bool = true
    ) {
        self.gateway = gateway
        self.auditLedger = auditLedger
        self.journal = journal
        self.auditExporter = auditExporter
        self.sourceDocumentService = sourceDocumentService
        self.sourceTimeZone = sourceTimeZone
        var normalizedCalendar = calendar
        normalizedCalendar.timeZone = sourceTimeZone
        self.calendar = normalizedCalendar
        self.environmentProvider = environmentProvider
        self.persistentAuditAvailable = persistentAuditAvailable
    }

    var canRunPreflight: Bool {
        stage == .preflight && mappingResult != nil && manifest != nil && !isBusy
    }

    var canImport: Bool {
        stage == .preflight &&
        preflightReport != nil &&
        preflightReviewed &&
        (preflightSummary?.eligibleCount ?? 0) > 0 &&
        persistentAuditAvailable &&
        !isBusy
    }

    var canRunHistoricalNutritionNoonRepair: Bool {
        stage == .selectSource && !isBusy
    }

    func performHistoricalNutritionNoonRepairDeletion() async {
        guard canRunHistoricalNutritionNoonRepair else { return }
        await performBusyOperation {
            guard gateway.isHealthDataAvailable else {
                throw ImportWorkflowError.healthDataUnavailable
            }

            let request = try HistoricalNutritionNoonRepairPolicy.deletionRequest(calendar: calendar)
            try await gateway.requestAuthorization(read: request.types, write: request.types)
            let deleted = try await gateway.deleteAppAuthoredSamples(matching: request)
            self.repairSummary = HistoricalNutritionRepairSummary(
                deletedCount: deleted,
                expectedCount: HistoricalNutritionRepairSummary.expectedLegacySampleCount
            )
        }
    }

    func selectSource(url: URL) async {
        await performBusyOperation {
            let source = try sourceDocumentService.load(from: url)
            let parsed = try CSVParser.parse(data: source.data, sourceTimeZone: sourceTimeZone)
            let mapping = MappingEngine.map(parsedCSV: parsed)
            let manifest = ImportManifestFactory.make(
                source: source,
                parsedCSV: parsed,
                mappingResult: mapping,
                environment: environmentProvider()
            )

            self.sourceURL = url
            self.source = source
            self.parsedCSV = parsed
            self.mappingResult = mapping
            self.manifest = manifest
            self.preflightReport = nil
            self.importResult = nil
            self.verificationReport = nil
            self.preflightSummary = nil
            self.resultSummary = nil
            self.auditBundleURL = nil
            self.preflightReviewed = false
            self.reviewSummary = Self.makeReviewSummary(manifest: manifest, mapping: mapping)
            self.stage = .review
        }
    }

    func continueToPreflight() {
        guard reviewSummary != nil else {
            errorMessage = ImportWorkflowError.reviewRequired.localizedDescription
            return
        }
        errorMessage = nil
        preflightReviewed = false
        stage = .preflight
    }

    func returnToReview() {
        guard reviewSummary != nil else { return }
        errorMessage = nil
        preflightReviewed = false
        stage = .review
    }

    func runPreflight() async {
        await performBusyOperation {
            let report = try await buildFreshPreflight(requestAuthorization: true)
            self.preflightReport = report
            self.preflightSummary = Self.makePreflightSummary(report)
            self.preflightReviewed = false
            self.stage = .preflight
        }
    }

    func setPreflightReviewed(_ reviewed: Bool) {
        guard preflightReport != nil else {
            preflightReviewed = false
            return
        }
        preflightReviewed = reviewed
        if reviewed { errorMessage = nil }
    }

    func performImport() async {
        guard persistentAuditAvailable else {
            errorMessage = ImportWorkflowError.auditPersistenceUnavailable.localizedDescription
            return
        }
        guard stage == .preflight else {
            errorMessage = ImportWorkflowError.preflightRequired.localizedDescription
            return
        }
        guard let reviewedReport = preflightReport else {
            errorMessage = ImportWorkflowError.preflightRequired.localizedDescription
            return
        }
        guard preflightReviewed else {
            errorMessage = ImportWorkflowError.preflightReviewRequired.localizedDescription
            return
        }
        guard !reviewedReport.eligible.isEmpty else {
            errorMessage = ImportWorkflowError.noEligibleSamples.localizedDescription
            return
        }

        await performBusyOperation {
            let freshReport = try await buildFreshPreflight(requestAuthorization: false)
            guard freshReport == reviewedReport else {
                self.preflightReport = freshReport
                self.preflightSummary = Self.makePreflightSummary(freshReport)
                self.preflightReviewed = false
                throw ImportWorkflowError.preflightChanged
            }

            guard let selectedURL = sourceURL else { throw ImportWorkflowError.noSourceSelected }
            let coordinator = ImportCoordinator(
                calendar: calendar,
                journal: journal,
                auditLedger: auditLedger,
                currentSourceSHA256: {
                    try SourceDocumentService().load(from: selectedURL).sha256
                }
            )

            let importResult = try await coordinator.import(report: freshReport, gateway: gateway)
            self.importResult = importResult

            let verification = await VerificationEngine(auditLedger: auditLedger)
                .verify(importResult: importResult, gateway: gateway)
            self.verificationReport = verification
            self.resultSummary = Self.makeResultSummary(importResult: importResult, verification: verification)
            self.stage = .results

            do {
                self.auditBundleURL = try await auditExporter.export(
                    manifest: freshReport.manifest,
                    ledger: auditLedger,
                    verification: verification
                )
            } catch {
                self.auditBundleURL = nil
                self.errorMessage = "Import and verification completed, but the audit bundle could not be exported: \(Self.message(for: error))"
            }
        }
    }

    func reset() {
        sourceURL = nil
        source = nil
        parsedCSV = nil
        mappingResult = nil
        manifest = nil
        preflightReport = nil
        importResult = nil
        verificationReport = nil
        reviewSummary = nil
        preflightSummary = nil
        resultSummary = nil
        auditBundleURL = nil
        preflightReviewed = false
        repairSummary = nil
        isBusy = false
        errorMessage = nil
        stage = .selectSource
    }

    private func buildFreshPreflight(requestAuthorization: Bool) async throws -> PreflightReport {
        guard gateway.isHealthDataAvailable else { throw ImportWorkflowError.healthDataUnavailable }
        guard let mappingResult, let manifest else { throw ImportWorkflowError.noSourceSelected }

        let identifiers = Set(mappingResult.mappedCandidates.map(\.healthIdentifier))
        if requestAuthorization {
            try await gateway.requestAuthorization(read: identifiers, write: identifiers)
        }

        return try await PreflightEngine.run(
            mappingResult: mappingResult,
            manifest: manifest,
            calendar: calendar,
            gateway: gateway
        )
    }

    private func performBusyOperation(_ operation: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await operation()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private static func makeReviewSummary(
        manifest: ImportManifest,
        mapping: MappingResult
    ) -> SourceReviewSummary {
        SourceReviewSummary(
            filename: manifest.sourceFilename,
            fingerprintPrefix: String(manifest.sourceSHA256.prefix(12)),
            rowCount: manifest.rowCount,
            dateStart: manifest.sourceDateStart,
            dateEnd: manifest.sourceDateEnd,
            supportedMappingCount: Set(mapping.mappedCandidates.map(\.sourceColumn)).count,
            unsupportedMappingCount: mapping.unsupportedFields.count,
            mappingVersion: mapping.registryVersion,
            unsupportedFields: mapping.unsupportedFields
        )
    }

    private static func makePreflightSummary(_ report: PreflightReport) -> HealthPreflightSummary {
        HealthPreflightSummary(
            eligibleCount: report.count(.eligible),
            existingCount: report.count(.skippedExisting),
            missingCount: report.count(.skippedMissing),
            zeroPolicyCount: report.count(.skippedZeroPolicy),
            authorizationBlockedCount: report.count(.authorizationBlocked),
            unsupportedFieldCount: report.unsupportedFields.count,
            visibilityWarning: report.visibilityWarning
        )
    }

    private static func makeResultSummary(
        importResult: ImportResult,
        verification: VerificationReport
    ) -> ImportResultSummary {
        ImportResultSummary(
            runID: importResult.runID,
            importedCount: importResult.importedCount,
            skippedExistingCount: importResult.skippedExistingCount,
            skippedMissingCount: importResult.skippedMissingCount,
            skippedZeroPolicyCount: importResult.skippedZeroPolicyCount,
            authorizationBlockedCount: importResult.authorizationBlockedCount,
            verifiedCount: verification.verifiedCount,
            failedVerificationCount: verification.failedCount,
            isVerifiedComplete: verification.isVerifiedComplete
        )
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

#if canImport(HealthKit)
extension ImportViewModel {
    static func makeLive() -> ImportViewModel {
        let gateway = LiveHealthStoreGateway()
        let sourceTimeZone = TimeZone.autoupdatingCurrent
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = sourceTimeZone

        let fileManager = FileManager.default
        let supportRoot = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let persistenceRoot = supportRoot.appendingPathComponent("BioMIRBackfill", isDirectory: true)
        let exportRoot = persistenceRoot.appendingPathComponent("AuditExports", isDirectory: true)
        let ledgerURL = persistenceRoot.appendingPathComponent("audit-ledger.jsonl")
        let journalURL = persistenceRoot.appendingPathComponent("import-journal.jsonl")

        do {
            try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)
            let probeURL = persistenceRoot.appendingPathComponent(".audit-write-probe-\(UUID().uuidString)")
            try Data("BioMIR Backfill audit persistence probe".utf8).write(to: probeURL, options: .atomic)
            try fileManager.removeItem(at: probeURL)

            let ledger = try AuditLedger(storageURL: ledgerURL)
            let journal = try ImportJournal(storageURL: journalURL)
            return ImportViewModel(
                gateway: gateway,
                auditLedger: ledger,
                journal: journal,
                auditExporter: AuditExporter(baseDirectory: exportRoot),
                sourceTimeZone: sourceTimeZone,
                calendar: calendar,
                environmentProvider: liveEnvironment
            )
        } catch {
            let ledger = try! AuditLedger(storageURL: nil)
            let journal = try! ImportJournal(storageURL: nil)
            let model = ImportViewModel(
                gateway: gateway,
                auditLedger: ledger,
                journal: journal,
                auditExporter: AuditExporter(baseDirectory: fileManager.temporaryDirectory),
                sourceTimeZone: sourceTimeZone,
                calendar: calendar,
                environmentProvider: liveEnvironment,
                persistentAuditAvailable: false
            )
            model.errorMessage = "Local audit persistence could not be initialized. Import is disabled until the app is restarted successfully."
            return model
        }
    }

    private static func liveEnvironment() -> ImportManifestEnvironment {
        ImportManifestEnvironment(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            generatedAt: Date()
        )
    }
}
#endif
