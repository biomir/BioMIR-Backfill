import Foundation

@main
struct CarbManagerTotalCarbHarness {
    static func main() throws {
        precondition(NutritionMappingRegistry.version == "nutrition-v0.1")
        precondition(NutritionMappingRegistry.supportedDefinitions.count == 31)
        precondition(!NutritionMappingRegistry.supportedDefinitions.contains { $0.healthIdentifier == .dietaryCarbohydrates })

        precondition(CarbManagerCarbohydrateMappingRegistry.version == "carbmanager-total-carb-v1")
        precondition(CarbManagerCarbohydrateMappingRegistry.sourceColumn == "Carb Manager Total Carbohydrates (g)")
        precondition(CarbManagerCarbohydrateMappingRegistry.definition.healthIdentifier == .dietaryCarbohydrates)
        precondition(CarbManagerCarbohydrateMappingRegistry.definition.transformationID == "carbmanager-total-carb-reconstruction-v1")

        // Deliberately use CRLF because Swift Character segmentation treats CRLF
        // as one grapheme cluster; this guards the production CSV tokenizer path.
        let csv = "Date,Carb Manager Total Carbohydrates (g)\r\n2021-03-11,59.9\r\n2023-09-26,\r\n"
        let parsed = try CSVParser.parse(data: Data(csv.utf8), sourceTimeZone: TimeZone(identifier: "America/New_York")!)
        let result = MappingEngine.map(parsedCSV: parsed)
        precondition(result.registryVersion == "carbmanager-total-carb-v1")
        precondition(result.unsupportedFields.isEmpty)
        precondition(result.mappedCandidates.count == 2)
        let first = result.mappedCandidates[0]
        precondition(first.healthIdentifier == .dietaryCarbohydrates)
        precondition(first.cellState == .value(59.9))
        precondition(first.normalizedValue == 59.9)
        precondition(first.transformationID == "carbmanager-total-carb-reconstruction-v1")
        precondition(result.mappedCandidates[1].cellState == .missing)

        let mixed = """
        Date,Carb Manager Total Carbohydrates (g),Fiber (g)
        2021-03-11,59.9,15.7
        """
        let mixedParsed = try CSVParser.parse(data: Data(mixed.utf8), sourceTimeZone: TimeZone(identifier: "America/New_York")!)
        let mixedResult = MappingEngine.map(parsedCSV: mixedParsed)
        precondition(mixedResult.registryVersion == "carbmanager-total-carb-v1")
        precondition(mixedResult.mappedCandidates.isEmpty)
        precondition(mixedResult.unsupportedFields.count == 2)

        let standard = """
        Date,Net Carbs (g),Fiber (g)
        2021-03-11,43.9,15.7
        """
        let standardParsed = try CSVParser.parse(data: Data(standard.utf8), sourceTimeZone: TimeZone(identifier: "America/New_York")!)
        let standardResult = MappingEngine.map(parsedCSV: standardParsed)
        precondition(standardResult.registryVersion == "nutrition-v0.1")
        precondition(standardResult.mappedCandidates.count == 1)
        precondition(standardResult.mappedCandidates[0].healthIdentifier == .dietaryFiber)
        precondition(standardResult.unsupportedFields.contains { $0.sourceColumn == "Net Carbs (g)" })

        print("CARB MANAGER TOTAL-CARB PROFILE PORTABLE: PASS")
    }
}
