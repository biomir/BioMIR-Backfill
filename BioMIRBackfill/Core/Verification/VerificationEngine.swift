import Foundation

final class VerificationEngine {
    private let auditLedger: AuditLedger?

    init(auditLedger: AuditLedger? = nil) {
        self.auditLedger = auditLedger
    }

    func verify(
        importResult: ImportResult,
        gateway: HealthStoreGateway
    ) async -> VerificationReport {
        let expectations = importResult.verificationExpectations
        guard !expectations.isEmpty else {
            return VerificationReport(
                runID: importResult.runID,
                generatedAt: Date(),
                expectedCount: 0,
                verifiedCount: 0,
                failedCount: 0,
                isVerifiedComplete: false,
                items: []
            )
        }

        let externalIDs = Set(expectations.compactMap { $0.draft.externalID })
        var unitsByType: [HealthQuantityKey: ControlledUnit] = [:]
        for expectation in expectations {
            unitsByType[expectation.draft.typeIdentifier] = expectation.draft.unit
        }

        let observed: [HealthSampleSummary]
        do {
            observed = try await gateway.samplesAuthoredByThisApp(
                externalIDs: externalIDs,
                unitsByType: unitsByType
            )
        } catch {
            var items: [VerificationItemResult] = []
            for expectation in expectations {
                items.append(await failedResult(
                    expectation: expectation,
                    runID: importResult.runID,
                    reasons: [.queryFailed],
                    observedUUID: nil,
                    detail: "HealthKit verification query failed: \(String(describing: error))"
                ))
            }
            return makeReport(runID: importResult.runID, items: items)
        }

        var observedByExternalID: [String: [HealthSampleSummary]] = [:]
        var observedWithoutExternalID: [HealthSampleSummary] = []
        for sample in observed {
            if let externalID = sample.externalID {
                observedByExternalID[externalID, default: []].append(sample)
            } else {
                observedWithoutExternalID.append(sample)
            }
        }

        var items: [VerificationItemResult] = []
        for expectation in expectations {
            guard let externalID = expectation.draft.externalID else {
                items.append(await failedResult(
                    expectation: expectation,
                    runID: importResult.runID,
                    reasons: [.externalIdentityMismatch],
                    observedUUID: nil,
                    detail: "Expected imported draft had no deterministic external identity."
                ))
                continue
            }

            var matches = observedByExternalID[externalID, default: []]
            if matches.isEmpty, observed.count == 1, observedWithoutExternalID.count == 1 {
                // This path exists only so a malformed result returned by the gateway cannot
                // be silently treated as a missing sample instead of an identity mismatch.
                matches = observedWithoutExternalID
            }

            if matches.isEmpty {
                items.append(await failedResult(
                    expectation: expectation,
                    runID: importResult.runID,
                    reasons: [.missingSample],
                    observedUUID: nil,
                    detail: "No app-authored HealthKit sample was returned for the external identity."
                ))
                continue
            }

            if matches.count != 1 {
                items.append(await failedResult(
                    expectation: expectation,
                    runID: importResult.runID,
                    reasons: [.duplicateExternalIdentity],
                    observedUUID: matches.first?.uuid.uuidString.lowercased(),
                    detail: "Expected exactly one app-authored sample for the external identity; found \(matches.count)."
                ))
                continue
            }

            let sample = matches[0]
            let reasons = mismatchReasons(expected: expectation.draft, observed: sample)
            if reasons.isEmpty {
                items.append(VerificationItemResult(
                    externalID: externalID,
                    rowNumber: expectation.rowNumber,
                    sourceColumn: expectation.sourceColumn,
                    sourceDate: expectation.sourceDate,
                    healthIdentifier: expectation.draft.typeIdentifier.rawValue,
                    status: .verified,
                    failureReasons: [],
                    observedSampleUUID: sample.uuid.uuidString.lowercased()
                ))
            } else {
                items.append(await failedResult(
                    expectation: expectation,
                    runID: importResult.runID,
                    reasons: reasons,
                    observedUUID: sample.uuid.uuidString.lowercased(),
                    detail: "Post-write reconciliation mismatch: \(reasons.map(\.rawValue).joined(separator: ", "))."
                ))
            }
        }

        return makeReport(runID: importResult.runID, items: items)
    }

    private func mismatchReasons(
        expected: HealthSampleDraft,
        observed: HealthSampleSummary
    ) -> [VerificationFailureReason] {
        var reasons: [VerificationFailureReason] = []
        if observed.typeIdentifier != expected.typeIdentifier { reasons.append(.typeMismatch) }
        if observed.value != expected.value { reasons.append(.valueMismatch) }
        if observed.unit != expected.unit { reasons.append(.unitMismatch) }
        if observed.startDate != expected.startDate { reasons.append(.startDateMismatch) }
        if observed.endDate != expected.endDate { reasons.append(.endDateMismatch) }
        if observed.externalID != expected.externalID { reasons.append(.externalIdentityMismatch) }
        if observed.wasUserEntered != expected.wasUserEntered { reasons.append(.userEnteredMismatch) }
        if observed.stringMetadata != expected.stringMetadata { reasons.append(.provenanceMismatch) }
        return reasons
    }

    private func failedResult(
        expectation: ImportedSampleExpectation,
        runID: UUID,
        reasons: [VerificationFailureReason],
        observedUUID: String?,
        detail: String
    ) async -> VerificationItemResult {
        var finalReasons = reasons
        if let auditLedger {
            let externalID = expectation.draft.externalID ?? "missing-external-id-row-\(expectation.rowNumber)"
            do {
                try await auditLedger.append(AuditRecord(
                    eventID: UUID(),
                    runID: runID,
                    subjectKey: externalID,
                    externalID: expectation.draft.externalID,
                    rowNumber: expectation.rowNumber,
                    sourceColumn: expectation.sourceColumn,
                    sourceDate: expectation.sourceDate,
                    healthIdentifier: expectation.draft.typeIdentifier.rawValue,
                    disposition: .verificationFailed,
                    batchID: expectation.batchID,
                    timestamp: Date(),
                    detail: detail
                ))
            } catch {
                if !finalReasons.contains(.auditPersistenceFailed) {
                    finalReasons.append(.auditPersistenceFailed)
                }
            }
        }

        return VerificationItemResult(
            externalID: expectation.draft.externalID ?? "",
            rowNumber: expectation.rowNumber,
            sourceColumn: expectation.sourceColumn,
            sourceDate: expectation.sourceDate,
            healthIdentifier: expectation.draft.typeIdentifier.rawValue,
            status: .verificationFailed,
            failureReasons: finalReasons,
            observedSampleUUID: observedUUID
        )
    }

    private func makeReport(runID: UUID, items: [VerificationItemResult]) -> VerificationReport {
        let verifiedCount = items.lazy.filter { $0.status == .verified }.count
        let failedCount = items.count - verifiedCount
        return VerificationReport(
            runID: runID,
            generatedAt: Date(),
            expectedCount: items.count,
            verifiedCount: verifiedCount,
            failedCount: failedCount,
            isVerifiedComplete: !items.isEmpty && failedCount == 0 && verifiedCount == items.count,
            items: items
        )
    }
}
