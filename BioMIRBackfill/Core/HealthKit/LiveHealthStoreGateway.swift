import Foundation
import HealthKit

final class LiveHealthStoreGateway: HealthStoreGateway, Sendable {
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization(
        read: Set<HealthQuantityKey>,
        write: Set<HealthQuantityKey>
    ) async throws {
        let readTypes = Set(read.compactMap { quantityType(for: $0) as HKObjectType? })
        let writeTypes = Set(write.compactMap { quantityType(for: $0) as HKSampleType? })
        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    func writeAuthorizationStatus(
        for identifier: HealthQuantityKey
    ) -> HealthWriteAuthorizationStatus {
        guard let type = quantityType(for: identifier) else {
            return .sharingDenied
        }

        switch healthStore.authorizationStatus(for: type) {
        case .notDetermined:
            return .notDetermined
        case .sharingDenied:
            return .sharingDenied
        case .sharingAuthorized:
            return .sharingAuthorized
        @unknown default:
            return .notDetermined
        }
    }

    func readVisibility(
        for identifiers: Set<HealthQuantityKey>
    ) async throws -> HealthReadVisibility {
        // HealthKit intentionally conceals whether read access is full or denied.
        // Xcode 26.3 / iOS 26.2 SDK does not expose the iOS 27 limited-history API.
        // Never infer "full access" from an empty query result.
        .unverifiable
    }

    func existingSamples(
        type: HealthQuantityKey,
        unit: ControlledUnit,
        start: Date,
        end: Date
    ) async throws -> [HealthSampleSummary] {
        guard let quantityType = quantityType(for: type) else {
            throw HealthStoreGatewayError.unsupportedType(type)
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: []
        )

        let samples: [HKQuantitySample] = try await querySamples(
            type: quantityType,
            predicate: predicate
        )

        return samples.map {
            summary(from: $0, type: type, unit: unit)
        }
    }

    func save(_ samples: [HealthSampleDraft]) async throws {
        let objects: [HKObject] = try samples.map { draft in
            guard let quantityType = quantityType(for: draft.typeIdentifier) else {
                throw HealthStoreGatewayError.unsupportedType(draft.typeIdentifier)
            }

            var metadata: [String: Any] = draft.stringMetadata
            metadata[HKMetadataKeyWasUserEntered] = draft.wasUserEntered
            if let externalID = draft.externalID {
                metadata[HKMetadataKeyExternalUUID] = externalID
            }

            return HKQuantitySample(
                type: quantityType,
                quantity: HKQuantity(unit: hkUnit(for: draft.unit), doubleValue: draft.value),
                start: draft.startDate,
                end: draft.endDate,
                metadata: metadata
            )
        }

        try await healthStore.save(objects)
    }

    func samplesAuthoredByThisApp(
        externalIDs: Set<String>,
        unitsByType: [HealthQuantityKey: ControlledUnit]
    ) async throws -> [HealthSampleSummary] {
        guard !externalIDs.isEmpty else { return [] }

        let metadataPredicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: Array(externalIDs)
        )
        let sourcePredicate = HKQuery.predicateForObjects(from: HKSource.default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [metadataPredicate, sourcePredicate])

        var combined: [HealthSampleSummary] = []
        for (type, unit) in unitsByType {
            guard let quantityType = quantityType(for: type) else { continue }
            let samples: [HKQuantitySample] = try await querySamples(
                type: quantityType,
                predicate: predicate
            )
            combined.append(contentsOf: samples.map {
                summary(from: $0, type: type, unit: unit)
            })
        }
        return combined
    }

    func deleteAppAuthoredSamples(
        matching request: HistoricalSampleDeletionRequest
    ) async throws -> Int {
        let sourcePredicate = HKQuery.predicateForObjects(from: HKSource.default())
        let classificationPredicate = HKQuery.predicateForObjects(
            withMetadataKey: ProvenanceService.MetadataKey.classification,
            allowedValues: [request.classification]
        )
        let mappingPredicate = HKQuery.predicateForObjects(
            withMetadataKey: ProvenanceService.MetadataKey.mappingVersion,
            allowedValues: Array(request.mappingVersions)
        )
        let datePredicate = HKQuery.predicateForSamples(
            withStart: request.startDate,
            end: request.endDate,
            options: .strictStartDate
        )
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            sourcePredicate,
            classificationPredicate,
            mappingPredicate,
            datePredicate
        ])

        var deletedCount = 0
        for type in request.types.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let quantityType = quantityType(for: type) else {
                throw HealthStoreGatewayError.unsupportedType(type)
            }

            let samples: [HKQuantitySample] = try await querySamples(
                type: quantityType,
                predicate: predicate
            )

            // Recovery is deliberately limited to the legacy full-day representation.
            // New noon-point samples carry the anchor-policy metadata and have start == end,
            // so rerunning this recovery cannot delete the corrected representation.
            let legacyFullDaySamples: [HKObject] = samples.filter { sample in
                let anchorPolicy = sample.metadata?[ProvenanceService.MetadataKey.timeAnchorPolicy] as? String
                return anchorPolicy == nil && sample.startDate < sample.endDate
            }

            guard !legacyFullDaySamples.isEmpty else { continue }
            try await delete(legacyFullDaySamples)
            deletedCount += legacyFullDaySamples.count
        }

        return deletedCount
    }

    private func delete(_ objects: [HKObject]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.delete(objects) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthStoreGatewayError.deleteFailed)
                }
            }
        }
    }

    private func querySamples(
        type: HKQuantityType,
        predicate: NSPredicate?
    ) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func summary(
        from sample: HKQuantitySample,
        type: HealthQuantityKey,
        unit: ControlledUnit
    ) -> HealthSampleSummary {
        HealthSampleSummary(
            uuid: sample.uuid,
            typeIdentifier: type,
            value: sample.quantity.doubleValue(for: hkUnit(for: unit)),
            unit: unit,
            startDate: sample.startDate,
            endDate: sample.endDate,
            sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
            externalID: sample.metadata?[HKMetadataKeyExternalUUID] as? String,
            wasUserEntered: sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool,
            stringMetadata: controlledStringMetadata(from: sample.metadata)
        )
    }

    private func controlledStringMetadata(from metadata: [String: Any]?) -> [String: String] {
        guard let metadata else { return [:] }
        var controlled: [String: String] = [:]
        for (key, value) in metadata where key.hasPrefix("co.biomir.backfill.") {
            if let string = value as? String { controlled[key] = string }
        }
        return controlled
    }

    private func quantityType(for key: HealthQuantityKey) -> HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: hkIdentifier(for: key))
    }

    private func hkIdentifier(for key: HealthQuantityKey) -> HKQuantityTypeIdentifier {
        switch key {
        case .dietaryEnergyConsumed: return .dietaryEnergyConsumed
        case .dietaryCarbohydrates: return .dietaryCarbohydrates
        case .dietaryFiber: return .dietaryFiber
        case .dietarySugar: return .dietarySugar
        case .dietaryFatTotal: return .dietaryFatTotal
        case .dietaryFatMonounsaturated: return .dietaryFatMonounsaturated
        case .dietaryFatPolyunsaturated: return .dietaryFatPolyunsaturated
        case .dietaryFatSaturated: return .dietaryFatSaturated
        case .dietaryCholesterol: return .dietaryCholesterol
        case .dietaryProtein: return .dietaryProtein
        case .dietaryVitaminA: return .dietaryVitaminA
        case .dietaryThiamin: return .dietaryThiamin
        case .dietaryRiboflavin: return .dietaryRiboflavin
        case .dietaryNiacin: return .dietaryNiacin
        case .dietaryPantothenicAcid: return .dietaryPantothenicAcid
        case .dietaryVitaminB6: return .dietaryVitaminB6
        case .dietaryVitaminB12: return .dietaryVitaminB12
        case .dietaryVitaminC: return .dietaryVitaminC
        case .dietaryVitaminD: return .dietaryVitaminD
        case .dietaryVitaminE: return .dietaryVitaminE
        case .dietaryVitaminK: return .dietaryVitaminK
        case .dietaryFolate: return .dietaryFolate
        case .dietaryCalcium: return .dietaryCalcium
        case .dietaryIron: return .dietaryIron
        case .dietaryMagnesium: return .dietaryMagnesium
        case .dietaryPhosphorus: return .dietaryPhosphorus
        case .dietaryPotassium: return .dietaryPotassium
        case .dietarySodium: return .dietarySodium
        case .dietaryZinc: return .dietaryZinc
        case .dietaryCopper: return .dietaryCopper
        case .dietarySelenium: return .dietarySelenium
        case .dietaryWater: return .dietaryWater
        }
    }

    private func hkUnit(for unit: ControlledUnit) -> HKUnit {
        switch unit {
        case .kilocalorie:
            return .kilocalorie()
        case .gram:
            return .gram()
        case .milligram:
            return .gramUnit(with: .milli)
        case .microgram:
            return .gramUnit(with: .micro)
        case .milliliter:
            return .literUnit(with: .milli)
        }
    }
}

enum HealthStoreGatewayError: Error, Equatable {
    case unsupportedType(HealthQuantityKey)
    case deleteFailed
}
