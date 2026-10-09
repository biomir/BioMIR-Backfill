import Foundation

enum MappingEngine {
    static func map(parsedCSV: ParsedCSV) -> MappingResult {
        if parsedCSV.headers.contains(CarbManagerCarbohydrateMappingRegistry.sourceColumn) {
            return mapCarbManagerTotalCarbohydrate(parsedCSV: parsedCSV)
        }

        return mapStandardNutrition(parsedCSV: parsedCSV)
    }

    private static func mapCarbManagerTotalCarbohydrate(parsedCSV: ParsedCSV) -> MappingResult {
        guard CarbManagerCarbohydrateMappingRegistry.matchesExactSchema(parsedCSV.headers) else {
            let reason = "carbmanager-total-carb-v1 requires exact Date + Carb Manager Total Carbohydrates (g) schema"
            return MappingResult(
                mappedCandidates: [],
                unsupportedFields: parsedCSV.headers
                    .filter { $0 != "Date" }
                    .map { UnsupportedField(sourceColumn: $0, reason: reason) },
                registryVersion: CarbManagerCarbohydrateMappingRegistry.version
            )
        }

        let definition = CarbManagerCarbohydrateMappingRegistry.definition
        let candidates = parsedCSV.rows.map { row in
            let state = row.cells[definition.sourceColumn] ?? .missing
            let normalizedValue: Double?

            switch state {
            case .missing:
                normalizedValue = nil
            case .explicitZero:
                normalizedValue = definition.normalize(0)
            case .value(let value):
                normalizedValue = definition.normalize(value)
            }

            return MappedCandidate(
                rowNumber: row.rowNumber,
                sourceDate: row.sourceDate,
                sourceColumn: definition.sourceColumn,
                healthIdentifier: definition.healthIdentifier,
                cellState: state,
                originalUnit: definition.sourceUnit,
                healthUnit: definition.healthUnit,
                normalizedValue: normalizedValue,
                transformationID: definition.transformationID,
                transformationVersion: definition.transformationVersion
            )
        }

        return MappingResult(
            mappedCandidates: candidates,
            unsupportedFields: [],
            registryVersion: CarbManagerCarbohydrateMappingRegistry.version
        )
    }

    private static func mapStandardNutrition(parsedCSV: ParsedCSV) -> MappingResult {
        var mappedCandidates: [MappedCandidate] = []
        var unsupportedFields: [UnsupportedField] = []

        for header in parsedCSV.headers where header != "Date" {
            guard let definition = NutritionMappingRegistry.definition(for: header) else {
                unsupportedFields.append(
                    UnsupportedField(
                        sourceColumn: header,
                        reason: NutritionMappingRegistry.unsupportedReason(for: header)
                            ?? "no controlled mapping in \(NutritionMappingRegistry.version)"
                    )
                )
                continue
            }

            for row in parsedCSV.rows {
                let state = row.cells[header] ?? .missing
                let normalizedValue: Double?

                switch state {
                case .missing:
                    normalizedValue = nil
                case .explicitZero:
                    normalizedValue = definition.normalize(0)
                case .value(let value):
                    normalizedValue = definition.normalize(value)
                }

                mappedCandidates.append(
                    MappedCandidate(
                        rowNumber: row.rowNumber,
                        sourceDate: row.sourceDate,
                        sourceColumn: definition.sourceColumn,
                        healthIdentifier: definition.healthIdentifier,
                        cellState: state,
                        originalUnit: definition.sourceUnit,
                        healthUnit: definition.healthUnit,
                        normalizedValue: normalizedValue,
                        transformationID: definition.transformationID,
                        transformationVersion: definition.transformationVersion
                    )
                )
            }
        }

        return MappingResult(
            mappedCandidates: mappedCandidates,
            unsupportedFields: unsupportedFields,
            registryVersion: NutritionMappingRegistry.version
        )
    }
}
