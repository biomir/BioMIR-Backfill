import XCTest
@testable import BioMIRBackfill

final class HealthAuthorizationStateTests: XCTestCase {
    func testAllRequestedWritesAuthorizedRequiresEveryRequestedTypeAuthorized() {
        let authorized = HealthAuthorizationState(
            healthDataAvailable: true,
            writeStatusByIdentifier: [
                .dietaryEnergyConsumed: .sharingAuthorized,
                .dietarySodium: .sharingAuthorized
            ],
            readVisibility: .unverifiable
        )
        XCTAssertTrue(authorized.allRequestedWritesAuthorized)

        let denied = HealthAuthorizationState(
            healthDataAvailable: true,
            writeStatusByIdentifier: [
                .dietaryEnergyConsumed: .sharingAuthorized,
                .dietarySodium: .sharingDenied
            ],
            readVisibility: .unverifiable
        )
        XCTAssertFalse(denied.allRequestedWritesAuthorized)
    }

    func testEmptyWriteSetIsNotTreatedAsAuthorized() {
        let state = HealthAuthorizationState(
            healthDataAvailable: true,
            writeStatusByIdentifier: [:],
            readVisibility: .unverifiable
        )
        XCTAssertFalse(state.allRequestedWritesAuthorized)
    }

    func testReadVisibilityCanRemainExplicitlyUnverifiable() {
        let state = HealthAuthorizationState(
            healthDataAvailable: true,
            writeStatusByIdentifier: [.dietarySodium: .sharingAuthorized],
            readVisibility: .unverifiable
        )
        XCTAssertEqual(state.readVisibility, .unverifiable)
    }
}
