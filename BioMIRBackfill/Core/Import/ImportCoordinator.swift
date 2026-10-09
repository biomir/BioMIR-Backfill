import Foundation

enum ImportCoordinatorError: Error, Equatable {
    case invalidBatchSize(Int)
    case batchWriteFailed
}

final class ImportCoordinator {
    static let defaultBatchSize = 200
    static let allowedBatchSize = 100...250

    private let calendar: Calendar
    private let journal: ImportJournal
    private let auditLedger: AuditLedger
    private let currentSourceSHA256: @Sendable () throws -> String

    init(
        calendar: Calendar,
        journal: ImportJournal,
        auditLedger: AuditLedger,
        currentSourceSHA256: @escaping @Sendable () throws -> String
    ) {
        self.calendar = calendar
        self.journal = journal
        self.auditLedger = auditLedger
        self.currentSourceSHA256 = currentSourceSHA256
    }

    func `import`(
        report: PreflightReport,
        batchSize: Int = ImportCoordinator.defaultBatchSize,
        gateway: HealthStoreGateway
    ) async throws -> ImportResult {
        guard Self.allowedBatchSize.contains(batchSize) else {
            throw ImportCoordinatorError.invalidBatchSize(batchSize)
        }

        let currentHash = try currentSourceSHA256()
        try SourceIntegrityGate.assertUnchanged(reviewedManifest: report.manifest, currentSHA256: currentHash)

        let runID = UUID()
        var importedCount = 0
        var skippedExistingCount = 0
        var skippedMissingCount = 0
        var skippedZeroPolicyCount = 0
        var authorizationBlockedCount = 0
        var importedExternalIDs: [String] = []
        var verificationExpectations: [ImportedSampleExpectation] = []

        for record in report.dispositions where record.disposition != .eligible {
            let disposition = auditDisposition(for: record.disposition)
            if disposition == .skippedExisting { skippedExistingCount += 1 }
            if disposition == .skippedMissing { skippedMissingCount += 1 }
            if disposition == .skippedZeroPolicy { skippedZeroPolicyCount += 1 }
            if disposition == .authorizationBlocked { authorizationBlockedCount += 1 }
            try await auditLedger.append(auditRecord(
                runID: runID,
                candidate: record.candidate,
                externalID: ProvenanceService.externalUUID(for: record.candidate, manifest: report.manifest),
                disposition: disposition,
                batchID: nil,
                detail: nil
            ))
        }

        var authorized: [(candidate: MappedCandidate, externalID: String)] = []
        for candidate in report.eligible {
            let externalID = ProvenanceService.externalUUID(for: candidate, manifest: report.manifest)
            guard gateway.writeAuthorizationStatus(for: candidate.healthIdentifier) == .sharingAuthorized else {
                authorizationBlockedCount += 1
                try await auditLedger.append(auditRecord(
                    runID: runID, candidate: candidate, externalID: externalID,
                    disposition: .authorizationBlocked, batchID: nil,
                    detail: "Write authorization was not available at import time."
                ))
                continue
            }
            authorized.append((candidate, externalID))
        }

        let externalIDs = Set(authorized.map(\.externalID))
        var unitsByType: [HealthQuantityKey: ControlledUnit] = [:]
        for item in authorized { unitsByType[item.candidate.healthIdentifier] = item.candidate.healthUnit }
        let authored = try await gateway.samplesAuthoredByThisApp(
            externalIDs: externalIDs,
            unitsByType: unitsByType
        )
        let authoredIDs = Set(authored.compactMap(\.externalID))

        var pending: [(candidate: MappedCandidate, externalID: String)] = []
        for item in authorized {
            if authoredIDs.contains(item.externalID) {
                skippedExistingCount += 1
                try await auditLedger.append(auditRecord(
                    runID: runID, candidate: item.candidate, externalID: item.externalID,
                    disposition: .skippedExisting, batchID: nil,
                    detail: "Deterministic app-authored external identity already exists."
                ))
            } else {
                pending.append(item)
            }
        }

        var batchStart = 0
        while batchStart < pending.count {
            let batchEnd = min(batchStart + batchSize, pending.count)
            let slice = Array(pending[batchStart..<batchEnd])
            let batchID = UUID()
            let drafts = try slice.map { item in
                try makeDraft(
                    candidate: item.candidate,
                    externalID: item.externalID,
                    batchID: batchID,
                    manifest: report.manifest
                )
            }

            try await journal.append(.started(
                eventID: UUID(), runID: runID, batchID: batchID,
                sourceSHA256: report.manifest.sourceSHA256,
                rangeStart: batchStart, rangeEndExclusive: batchEnd,
                plannedExternalIDs: slice.map(\.externalID), timestamp: Date()
            ))

            do {
                try await gateway.save(drafts)
            } catch {
                try? await journal.append(.failed(
                    eventID: UUID(), runID: runID, batchID: batchID, timestamp: Date(),
                    errorDescription: String(describing: error)
                ))
                for item in slice {
                    try? await auditLedger.append(auditRecord(
                        runID: runID, candidate: item.candidate, externalID: item.externalID,
                        disposition: .writeFailed, batchID: batchID,
                        detail: String(describing: error)
                    ))
                }
                throw ImportCoordinatorError.batchWriteFailed
            }

            // Once HealthKit save returns successfully, never relabel later local-persistence
            // failures as write failures. A missing terminal journal event represents an
            // uncertain local bookkeeping state and is recovered by fresh preflight.
            try await journal.append(.succeeded(
                eventID: UUID(), runID: runID, batchID: batchID, timestamp: Date()
            ))
            for (index, item) in slice.enumerated() {
                importedCount += 1
                importedExternalIDs.append(item.externalID)
                verificationExpectations.append(ImportedSampleExpectation(
                    rowNumber: item.candidate.rowNumber,
                    sourceColumn: item.candidate.sourceColumn,
                    sourceDate: ProvenanceService.isoDate(item.candidate.sourceDate),
                    batchID: batchID,
                    draft: drafts[index]
                ))
                try await auditLedger.append(auditRecord(
                    runID: runID, candidate: item.candidate, externalID: item.externalID,
                    disposition: .imported, batchID: batchID, detail: nil
                ))
            }
            batchStart = batchEnd
        }

        return ImportResult(
            runID: runID,
            importedCount: importedCount,
            skippedExistingCount: skippedExistingCount,
            skippedMissingCount: skippedMissingCount,
            skippedZeroPolicyCount: skippedZeroPolicyCount,
            authorizationBlockedCount: authorizationBlockedCount,
            externalIDs: importedExternalIDs,
            verificationExpectations: verificationExpectations
        )
    }

    private func makeDraft(
        candidate: MappedCandidate,
        externalID: String,
        batchID: UUID,
        manifest: ImportManifest
    ) throws -> HealthSampleDraft {
        let anchor = try CalendarDayInterval.noonAnchor(for: candidate.sourceDate, calendar: calendar)
        guard let value = candidate.normalizedValue else {
            preconditionFailure("Only normalized observed values may reach import coordination.")
        }
        let context = ProvenanceContext(batchID: batchID, candidate: candidate, manifest: manifest)
        return HealthSampleDraft(
            typeIdentifier: candidate.healthIdentifier,
            value: value,
            unit: candidate.healthUnit,
            startDate: anchor,
            endDate: anchor,
            externalID: externalID,
            wasUserEntered: true,
            stringMetadata: ProvenanceService.stringMetadata(for: context)
        )
    }

    private func auditRecord(
        runID: UUID,
        candidate: MappedCandidate,
        externalID: String,
        disposition: AuditDisposition,
        batchID: UUID?,
        detail: String?
    ) -> AuditRecord {
        AuditRecord(
            eventID: UUID(), runID: runID, subjectKey: externalID, externalID: externalID,
            rowNumber: candidate.rowNumber, sourceColumn: candidate.sourceColumn,
            sourceDate: ProvenanceService.isoDate(candidate.sourceDate),
            healthIdentifier: candidate.healthIdentifier.rawValue, disposition: disposition,
            batchID: batchID, timestamp: Date(), detail: detail
        )
    }

    private func auditDisposition(for disposition: PreflightDisposition) -> AuditDisposition {
        switch disposition {
        case .eligible: return .rejectedMapping // unreachable for this call site
        case .skippedExisting: return .skippedExisting
        case .skippedMissing: return .skippedMissing
        case .skippedZeroPolicy: return .skippedZeroPolicy
        case .unsupported: return .unsupported
        case .rejectedRange: return .rejectedRange
        case .rejectedUnit: return .rejectedUnit
        case .rejectedMapping: return .rejectedMapping
        case .authorizationBlocked: return .authorizationBlocked
        case .writeFailed: return .writeFailed
        case .verificationFailed: return .verificationFailed
        }
    }
}
