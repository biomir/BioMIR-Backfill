import Foundation

enum PreflightEngine {
    static let unverifiableVisibilityWarning =
        "Apple Health read visibility cannot be verified. Collision screening covers only samples visible to BioMIR Backfill."

    static let limitedVisibilityWarning =
        "Apple Health historical read visibility is limited. Collision screening covers only the authorized historical window visible to BioMIR Backfill."

    static func run(
        mappingResult: MappingResult,
        manifest: ImportManifest,
        calendar: Calendar,
        gateway: HealthStoreGateway
    ) async throws -> PreflightReport {
        let identifiers = Set(mappingResult.mappedCandidates.map(\.healthIdentifier))
        let readVisibility = try await gateway.readVisibility(for: identifiers)
        let warning: String?
        switch readVisibility {
        case .unverifiable:
            warning = unverifiableVisibilityWarning
        case .limited:
            warning = limitedVisibilityWarning
        }

        var records: [PreflightDispositionRecord] = []
        records.reserveCapacity(mappingResult.mappedCandidates.count)

        for candidate in mappingResult.mappedCandidates {
            switch candidate.cellState {
            case .missing:
                records.append(
                    PreflightDispositionRecord(
                        candidate: candidate,
                        disposition: .skippedMissing,
                        visibleExistingSampleCount: 0
                    )
                )

            case .explicitZero:
                records.append(
                    PreflightDispositionRecord(
                        candidate: candidate,
                        disposition: .skippedZeroPolicy,
                        visibleExistingSampleCount: 0
                    )
                )

            case .value:
                guard gateway.writeAuthorizationStatus(for: candidate.healthIdentifier) == .sharingAuthorized else {
                    records.append(
                        PreflightDispositionRecord(
                            candidate: candidate,
                            disposition: .authorizationBlocked,
                            visibleExistingSampleCount: 0
                        )
                    )
                    continue
                }

                let interval = try CalendarDayInterval.dayInterval(
                    for: candidate.sourceDate,
                    calendar: calendar
                )
                let existing = try await gateway.existingSamples(
                    type: candidate.healthIdentifier,
                    unit: candidate.healthUnit,
                    start: interval.start,
                    end: interval.end
                )

                records.append(
                    PreflightDispositionRecord(
                        candidate: candidate,
                        disposition: existing.isEmpty ? .eligible : .skippedExisting,
                        visibleExistingSampleCount: existing.count
                    )
                )
            }
        }

        return PreflightReport(
            manifest: manifest,
            dispositions: records,
            unsupportedFields: mappingResult.unsupportedFields,
            readVisibility: readVisibility,
            visibilityWarning: warning
        )
    }
}
