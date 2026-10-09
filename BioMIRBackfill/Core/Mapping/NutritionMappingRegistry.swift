import Foundation

enum NutritionMappingRegistry {
    static let version = "nutrition-v0.1"
    static let directTransformationVersion = "v1"

    static let supportedDefinitions: [NutritionMappingDefinition] = [
        direct("Dietary Calories (kCal)", .dietaryEnergyConsumed, sourceUnit: "kcal", healthUnit: .kilocalorie),
        direct("Fat (g)", .dietaryFatTotal, sourceUnit: "g", healthUnit: .gram),
        direct("Protein (g)", .dietaryProtein, sourceUnit: "g", healthUnit: .gram),
        direct("Fiber (g)", .dietaryFiber, sourceUnit: "g", healthUnit: .gram),
        direct("Sugar (g)", .dietarySugar, sourceUnit: "g", healthUnit: .gram),
        direct("Saturated Fat (g)", .dietaryFatSaturated, sourceUnit: "g", healthUnit: .gram),
        direct("Monounsat. Fat (g)", .dietaryFatMonounsaturated, sourceUnit: "g", healthUnit: .gram),
        direct("Polyunsat. Fat (g)", .dietaryFatPolyunsaturated, sourceUnit: "g", healthUnit: .gram),
        direct("Cholesterol (mg)", .dietaryCholesterol, sourceUnit: "mg", healthUnit: .milligram),
        direct("Calcium (mg)", .dietaryCalcium, sourceUnit: "mg", healthUnit: .milligram),
        direct("Iron (mg)", .dietaryIron, sourceUnit: "mg", healthUnit: .milligram),
        direct("Magnesium (mg)", .dietaryMagnesium, sourceUnit: "mg", healthUnit: .milligram),
        direct("Phosphorus (mg)", .dietaryPhosphorus, sourceUnit: "mg", healthUnit: .milligram),
        direct("Potassium (mg)", .dietaryPotassium, sourceUnit: "mg", healthUnit: .milligram),
        direct("Sodium (mg)", .dietarySodium, sourceUnit: "mg", healthUnit: .milligram),
        direct("Zinc (mg)", .dietaryZinc, sourceUnit: "mg", healthUnit: .milligram),
        direct("Copper (mg)", .dietaryCopper, sourceUnit: "mg", healthUnit: .milligram),
        direct("Selenium (µg)", .dietarySelenium, sourceUnit: "µg", healthUnit: .microgram),
        direct("Vitamin B9 [Folate] (µg)", .dietaryFolate, sourceUnit: "µg", healthUnit: .microgram),
        direct("Vitamin A [Retinoid] (µg)", .dietaryVitaminA, sourceUnit: "µg", healthUnit: .microgram),
        direct("Vitamin B1 [Thiamin] (mg)", .dietaryThiamin, sourceUnit: "mg", healthUnit: .milligram),
        direct("Vitamin B2 [Riboflavin] (mg)", .dietaryRiboflavin, sourceUnit: "mg", healthUnit: .milligram),
        direct("Vitamin B3 [Niacin] (mg)", .dietaryNiacin, sourceUnit: "mg", healthUnit: .milligram),
        direct("Vitamin B5 [Panto. Acid] (mg)", .dietaryPantothenicAcid, sourceUnit: "mg", healthUnit: .milligram),
        direct("Vitamin B6 [Pyridoxine] (mg)", .dietaryVitaminB6, sourceUnit: "mg", healthUnit: .milligram),
        direct("Vitamin B12 [Cobalamin] (µg)", .dietaryVitaminB12, sourceUnit: "µg", healthUnit: .microgram),
        direct("Vitamin C [Ascorbate] (mg)", .dietaryVitaminC, sourceUnit: "mg", healthUnit: .milligram),
        direct("Vitamin D [Calciferol] (µg)", .dietaryVitaminD, sourceUnit: "µg", healthUnit: .microgram),
        direct("Vitamin K [Phytonadion] (µg)", .dietaryVitaminK, sourceUnit: "µg", healthUnit: .microgram),
        direct("Vitamin E [Tocopherol] (mg)", .dietaryVitaminE, sourceUnit: "mg", healthUnit: .milligram),
        NutritionMappingDefinition(
            sourceColumn: "Water Consumed (8oz-glass)",
            healthIdentifier: .dietaryWater,
            sourceUnit: "8 US fl oz glass",
            healthUnit: .milliliter,
            multiplier: 236.5882365,
            transformationID: "water-us-fl-oz-to-ml-v1",
            transformationVersion: "v1"
        )
    ]

    static let unsupportedDefinitions: [UnsupportedMappingDefinition] = [
        .init(sourceColumn: "Net Carbs (g)", reason: "semantic mismatch with total carbohydrate"),
        .init(sourceColumn: "Added Sugar (g)", reason: "no controlled v1 mapping"),
        .init(sourceColumn: "Sugar Alcohols (g)", reason: "no controlled v1 mapping"),
        .init(sourceColumn: "Starch (g)", reason: "no controlled v1 mapping"),
        .init(sourceColumn: "Omega-3 Fat (g)", reason: "no controlled v1 mapping"),
        .init(sourceColumn: "Omega-6 Fat (g)", reason: "no controlled v1 mapping"),
        .init(sourceColumn: "Omega 6:3 Ratio", reason: "derived ratio"),
        .init(sourceColumn: "Glycemic Load", reason: "derived/semantic mismatch"),
        .init(sourceColumn: "Choline (mg)", reason: "no controlled v1 mapping")
    ]

    private static let supportedBySource: [String: NutritionMappingDefinition] = {
        Dictionary(uniqueKeysWithValues: supportedDefinitions.map { ($0.sourceColumn, $0) })
    }()

    private static let unsupportedBySource: [String: UnsupportedMappingDefinition] = {
        Dictionary(uniqueKeysWithValues: unsupportedDefinitions.map { ($0.sourceColumn, $0) })
    }()

    static func definition(for sourceColumn: String) -> NutritionMappingDefinition? {
        supportedBySource[sourceColumn]
    }

    static func unsupportedReason(for sourceColumn: String) -> String? {
        unsupportedBySource[sourceColumn]?.reason
    }

    private static func direct(
        _ sourceColumn: String,
        _ healthIdentifier: HealthQuantityKey,
        sourceUnit: String,
        healthUnit: ControlledUnit
    ) -> NutritionMappingDefinition {
        NutritionMappingDefinition(
            sourceColumn: sourceColumn,
            healthIdentifier: healthIdentifier,
            sourceUnit: sourceUnit,
            healthUnit: healthUnit,
            multiplier: 1,
            transformationID: "direct-v1",
            transformationVersion: directTransformationVersion
        )
    }
}

enum CarbManagerCarbohydrateMappingRegistry {
    static let version = "carbmanager-total-carb-v1"
    static let sourceColumn = "Carb Manager Total Carbohydrates (g)"
    static let requiredHeaders = Set(["Date", sourceColumn])

    static let definition = NutritionMappingDefinition(
        sourceColumn: sourceColumn,
        healthIdentifier: .dietaryCarbohydrates,
        sourceUnit: "g",
        healthUnit: .gram,
        multiplier: 1,
        transformationID: "carbmanager-total-carb-reconstruction-v1",
        transformationVersion: "v1"
    )

    static func matchesExactSchema(_ headers: [String]) -> Bool {
        headers.count == requiredHeaders.count && Set(headers) == requiredHeaders
    }
}
