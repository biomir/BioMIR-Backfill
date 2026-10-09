import Foundation

@main
struct Task3PortableHarness {
    static func main() throws {
        precondition(NutritionMappingRegistry.version == "nutrition-v0.1")
        precondition(NutritionMappingRegistry.supportedDefinitions.count == 31)
        precondition(NutritionMappingRegistry.unsupportedDefinitions.count == 9)
        precondition(NutritionMappingRegistry.definition(for: "Net Carbs (g)") == nil)
        precondition(NutritionMappingRegistry.unsupportedReason(for: "Net Carbs (g)") == "semantic mismatch with total carbohydrate")
        precondition(!NutritionMappingRegistry.supportedDefinitions.contains { $0.healthIdentifier == .dietaryCarbohydrates })

        let water = NutritionMappingRegistry.definition(for: "Water Consumed (8oz-glass)")!
        precondition(water.transformationID == "water-us-fl-oz-to-ml-v1")
        precondition(abs(water.normalize(3) - 709.7647095) < 1e-10)

        let csv = """
        Date,Dietary Calories (kCal),Sodium (mg),Water Consumed (8oz-glass),Net Carbs (g),Unknown Field
        2025-01-01,0,,3,20,9
        """
        let parsed = try CSVParser.parse(data: Data(csv.utf8), sourceTimeZone: TimeZone(identifier: "America/New_York")!)
        let result = MappingEngine.map(parsedCSV: parsed)
        precondition(result.registryVersion == "nutrition-v0.1")
        precondition(result.mappedCandidates.count == 3)
        precondition(result.unsupportedFields.count == 2)

        let calories = result.mappedCandidates.first { $0.sourceColumn == "Dietary Calories (kCal)" }!
        precondition(calories.cellState == .explicitZero)
        precondition(calories.normalizedValue == 0)

        let sodium = result.mappedCandidates.first { $0.sourceColumn == "Sodium (mg)" }!
        precondition(sodium.cellState == .missing)
        precondition(sodium.normalizedValue == nil)

        let mappedWater = result.mappedCandidates.first { $0.sourceColumn == "Water Consumed (8oz-glass)" }!
        precondition(mappedWater.cellState == .value(3))
        precondition(abs(mappedWater.normalizedValue! - 709.7647095) < 1e-10)

        precondition(result.unsupportedFields.contains { $0.sourceColumn == "Net Carbs (g)" && $0.reason == "semantic mismatch with total carbohydrate" })
        precondition(result.unsupportedFields.contains { $0.sourceColumn == "Unknown Field" && $0.reason == "no controlled mapping in nutrition-v0.1" })

        print("TASK 3 PORTABLE BEHAVIOR: PASS")
    }
}
