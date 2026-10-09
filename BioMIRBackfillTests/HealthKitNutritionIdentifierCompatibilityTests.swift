import HealthKit
import XCTest
@testable import BioMIRBackfill

final class HealthKitNutritionIdentifierCompatibilityTests: XCTestCase {
    func testCarbManagerTotalCarbohydrateMappingResolvesInCurrentHealthKitSDK() {
        let definition = CarbManagerCarbohydrateMappingRegistry.definition
        XCTAssertEqual(definition.healthIdentifier, .dietaryCarbohydrates)
        XCTAssertNotNil(
            HKObjectType.quantityType(forIdentifier: appleIdentifier(for: definition.healthIdentifier)),
            "HealthKit SDK did not resolve dietaryCarbohydrates for Carb Manager profile"
        )
    }

    func testEverySupportedNutritionMappingResolvesInCurrentHealthKitSDK() {
        XCTAssertEqual(NutritionMappingRegistry.supportedDefinitions.count, 31)

        for definition in NutritionMappingRegistry.supportedDefinitions {
            let appleIdentifier = appleIdentifier(for: definition.healthIdentifier)
            XCTAssertNotNil(
                HKObjectType.quantityType(forIdentifier: appleIdentifier),
                "HealthKit SDK did not resolve \(definition.healthIdentifier.rawValue)"
            )
        }
    }

    private func appleIdentifier(for key: HealthQuantityKey) -> HKQuantityTypeIdentifier {
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
}
