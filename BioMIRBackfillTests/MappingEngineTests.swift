import XCTest
@testable import BioMIRBackfill

final class MappingEngineTests: XCTestCase {
    func testControlledRegistryHasExactlyThirtyOneSupportedDefinitions() {
        XCTAssertEqual(NutritionMappingRegistry.version, "nutrition-v0.1")
        XCTAssertEqual(NutritionMappingRegistry.supportedDefinitions.count, 31)
        XCTAssertEqual(Set(NutritionMappingRegistry.supportedDefinitions.map(\.sourceColumn)).count, 31)
        XCTAssertEqual(Set(NutritionMappingRegistry.supportedDefinitions.map(\.healthIdentifier)).count, 31)
    }

    func testControlledRegistryMatchesApprovedHealthIdentifiersAndUnits() {
        let expected: [(String, HealthQuantityKey, ControlledUnit)] = [
            ("Dietary Calories (kCal)", .dietaryEnergyConsumed, .kilocalorie),
            ("Fat (g)", .dietaryFatTotal, .gram),
            ("Protein (g)", .dietaryProtein, .gram),
            ("Fiber (g)", .dietaryFiber, .gram),
            ("Sugar (g)", .dietarySugar, .gram),
            ("Saturated Fat (g)", .dietaryFatSaturated, .gram),
            ("Monounsat. Fat (g)", .dietaryFatMonounsaturated, .gram),
            ("Polyunsat. Fat (g)", .dietaryFatPolyunsaturated, .gram),
            ("Cholesterol (mg)", .dietaryCholesterol, .milligram),
            ("Calcium (mg)", .dietaryCalcium, .milligram),
            ("Iron (mg)", .dietaryIron, .milligram),
            ("Magnesium (mg)", .dietaryMagnesium, .milligram),
            ("Phosphorus (mg)", .dietaryPhosphorus, .milligram),
            ("Potassium (mg)", .dietaryPotassium, .milligram),
            ("Sodium (mg)", .dietarySodium, .milligram),
            ("Zinc (mg)", .dietaryZinc, .milligram),
            ("Copper (mg)", .dietaryCopper, .milligram),
            ("Selenium (µg)", .dietarySelenium, .microgram),
            ("Vitamin B9 [Folate] (µg)", .dietaryFolate, .microgram),
            ("Vitamin A [Retinoid] (µg)", .dietaryVitaminA, .microgram),
            ("Vitamin B1 [Thiamin] (mg)", .dietaryThiamin, .milligram),
            ("Vitamin B2 [Riboflavin] (mg)", .dietaryRiboflavin, .milligram),
            ("Vitamin B3 [Niacin] (mg)", .dietaryNiacin, .milligram),
            ("Vitamin B5 [Panto. Acid] (mg)", .dietaryPantothenicAcid, .milligram),
            ("Vitamin B6 [Pyridoxine] (mg)", .dietaryVitaminB6, .milligram),
            ("Vitamin B12 [Cobalamin] (µg)", .dietaryVitaminB12, .microgram),
            ("Vitamin C [Ascorbate] (mg)", .dietaryVitaminC, .milligram),
            ("Vitamin D [Calciferol] (µg)", .dietaryVitaminD, .microgram),
            ("Vitamin K [Phytonadion] (µg)", .dietaryVitaminK, .microgram),
            ("Vitamin E [Tocopherol] (mg)", .dietaryVitaminE, .milligram),
            ("Water Consumed (8oz-glass)", .dietaryWater, .milliliter)
        ]

        XCTAssertEqual(expected.count, 31)
        for (source, identifier, unit) in expected {
            let definition = NutritionMappingRegistry.definition(for: source)
            XCTAssertEqual(definition?.healthIdentifier, identifier, source)
            XCTAssertEqual(definition?.healthUnit, unit, source)
        }
    }

    func testNetCarbsAndDerivedFieldsRemainExplicitlyUnsupported() {
        XCTAssertNil(NutritionMappingRegistry.definition(for: "Net Carbs (g)"))
        XCTAssertEqual(
            NutritionMappingRegistry.unsupportedReason(for: "Net Carbs (g)"),
            "semantic mismatch with total carbohydrate"
        )
        XCTAssertNil(NutritionMappingRegistry.definition(for: "Omega 6:3 Ratio"))
        XCTAssertNil(NutritionMappingRegistry.definition(for: "Glycemic Load"))
        XCTAssertFalse(NutritionMappingRegistry.supportedDefinitions.contains { $0.healthIdentifier == .dietaryCarbohydrates })
    }

    func testWaterConversionUsesControlledConstantAndVersionedTransformation() throws {
        guard let definition = NutritionMappingRegistry.definition(for: "Water Consumed (8oz-glass)") else {
            return XCTFail("Water mapping missing")
        }

        XCTAssertEqual(definition.transformationID, "water-us-fl-oz-to-ml-v1")
        XCTAssertEqual(definition.multiplier, 236.5882365, accuracy: 0.0000000001)
        XCTAssertEqual(definition.normalize(1), 236.5882365, accuracy: 0.0000000001)
        XCTAssertEqual(definition.normalize(3), 709.7647095, accuracy: 0.0000000001)
    }

    func testMappingEnginePreservesMissingZeroAndObservedStates() throws {
        let csv = """
        Date,Dietary Calories (kCal),Sodium (mg),Water Consumed (8oz-glass)
        2025-01-01,0,,3
        """
        let parsed = try CSVParser.parse(
            data: Data(csv.utf8),
            sourceTimeZone: TimeZone(identifier: "America/New_York")!
        )

        let result = MappingEngine.map(parsedCSV: parsed)
        XCTAssertEqual(result.mappedCandidates.count, 3)
        XCTAssertTrue(result.unsupportedFields.isEmpty)

        let calories = try XCTUnwrap(result.mappedCandidates.first { $0.sourceColumn == "Dietary Calories (kCal)" })
        XCTAssertEqual(calories.cellState, .explicitZero)
        XCTAssertEqual(calories.normalizedValue, 0)

        let sodium = try XCTUnwrap(result.mappedCandidates.first { $0.sourceColumn == "Sodium (mg)" })
        XCTAssertEqual(sodium.cellState, .missing)
        XCTAssertNil(sodium.normalizedValue)

        let water = try XCTUnwrap(result.mappedCandidates.first { $0.sourceColumn == "Water Consumed (8oz-glass)" })
        XCTAssertEqual(water.cellState, .value(3))
        XCTAssertEqual(try XCTUnwrap(water.normalizedValue), 709.7647095, accuracy: 0.0000000001)
    }

    func testUnknownColumnIsReportedUnsupportedRatherThanInferred() throws {
        let csv = """
        Date,My Custom Nutrient
        2025-01-01,12
        """
        let parsed = try CSVParser.parse(
            data: Data(csv.utf8),
            sourceTimeZone: TimeZone(secondsFromGMT: 0)!
        )

        let result = MappingEngine.map(parsedCSV: parsed)
        XCTAssertTrue(result.mappedCandidates.isEmpty)
        XCTAssertEqual(result.unsupportedFields.count, 1)
        XCTAssertEqual(result.unsupportedFields[0].sourceColumn, "My Custom Nutrient")
        XCTAssertEqual(result.unsupportedFields[0].reason, "no controlled mapping in nutrition-v0.1")
    }
    func testCarbManagerTotalCarbohydrateProfileIsSeparateAndExactSchemaOnly() throws {
        XCTAssertEqual(CarbManagerCarbohydrateMappingRegistry.version, "carbmanager-total-carb-v1")
        XCTAssertEqual(CarbManagerCarbohydrateMappingRegistry.sourceColumn, "Carb Manager Total Carbohydrates (g)")
        XCTAssertEqual(CarbManagerCarbohydrateMappingRegistry.definition.healthIdentifier, .dietaryCarbohydrates)
        XCTAssertEqual(CarbManagerCarbohydrateMappingRegistry.definition.transformationID, "carbmanager-total-carb-reconstruction-v1")

        let csv = """
        Date,Carb Manager Total Carbohydrates (g)
        2021-03-11,59.9
        2023-09-26,
        """
        let parsed = try CSVParser.parse(
            data: Data(csv.utf8),
            sourceTimeZone: TimeZone(identifier: "America/New_York")!
        )

        let result = MappingEngine.map(parsedCSV: parsed)
        XCTAssertEqual(result.registryVersion, "carbmanager-total-carb-v1")
        XCTAssertTrue(result.unsupportedFields.isEmpty)
        XCTAssertEqual(result.mappedCandidates.count, 2)
        XCTAssertEqual(result.mappedCandidates[0].healthIdentifier, .dietaryCarbohydrates)
        XCTAssertEqual(result.mappedCandidates[0].cellState, .value(59.9))
        XCTAssertEqual(result.mappedCandidates[0].transformationID, "carbmanager-total-carb-reconstruction-v1")
        XCTAssertEqual(result.mappedCandidates[1].cellState, .missing)

        let mixed = """
        Date,Carb Manager Total Carbohydrates (g),Fiber (g)
        2021-03-11,59.9,15.7
        """
        let mixedParsed = try CSVParser.parse(
            data: Data(mixed.utf8),
            sourceTimeZone: TimeZone(identifier: "America/New_York")!
        )
        let mixedResult = MappingEngine.map(parsedCSV: mixedParsed)
        XCTAssertEqual(mixedResult.registryVersion, "carbmanager-total-carb-v1")
        XCTAssertTrue(mixedResult.mappedCandidates.isEmpty)
        XCTAssertEqual(mixedResult.unsupportedFields.count, 2)
    }

}
