import Foundation

enum HealthQuantityKey: String, CaseIterable, Hashable, Sendable {
    case dietaryEnergyConsumed
    case dietaryCarbohydrates
    case dietaryFiber
    case dietarySugar
    case dietaryFatTotal
    case dietaryFatMonounsaturated
    case dietaryFatPolyunsaturated
    case dietaryFatSaturated
    case dietaryCholesterol
    case dietaryProtein
    case dietaryVitaminA
    case dietaryThiamin
    case dietaryRiboflavin
    case dietaryNiacin
    case dietaryPantothenicAcid
    case dietaryVitaminB6
    case dietaryVitaminB12
    case dietaryVitaminC
    case dietaryVitaminD
    case dietaryVitaminE
    case dietaryVitaminK
    case dietaryFolate
    case dietaryCalcium
    case dietaryIron
    case dietaryMagnesium
    case dietaryPhosphorus
    case dietaryPotassium
    case dietarySodium
    case dietaryZinc
    case dietaryCopper
    case dietarySelenium
    case dietaryWater
}

enum ControlledUnit: String, Hashable, Sendable {
    case kilocalorie = "kcal"
    case gram = "g"
    case milligram = "mg"
    case microgram = "µg"
    case milliliter = "mL"
}

struct NutritionMappingDefinition: Equatable, Hashable, Sendable {
    let sourceColumn: String
    let healthIdentifier: HealthQuantityKey
    let sourceUnit: String
    let healthUnit: ControlledUnit
    let multiplier: Double
    let transformationID: String
    let transformationVersion: String

    func normalize(_ value: Double) -> Double {
        value * multiplier
    }
}

struct UnsupportedMappingDefinition: Equatable, Hashable, Sendable {
    let sourceColumn: String
    let reason: String
}

struct MappedCandidate: Equatable, Sendable {
    let rowNumber: Int
    let sourceDate: DateComponents
    let sourceColumn: String
    let healthIdentifier: HealthQuantityKey
    let cellState: CSVCellState
    let originalUnit: String
    let healthUnit: ControlledUnit
    let normalizedValue: Double?
    let transformationID: String
    let transformationVersion: String
}

struct UnsupportedField: Equatable, Sendable {
    let sourceColumn: String
    let reason: String
}

struct MappingResult: Equatable, Sendable {
    let mappedCandidates: [MappedCandidate]
    let unsupportedFields: [UnsupportedField]
    let registryVersion: String
}
