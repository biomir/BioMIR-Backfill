import Foundation

@main
struct Task4Harness {
    static func main() {
        let state = HealthAuthorizationState(
            healthDataAvailable: true,
            writeStatusByIdentifier: [
                .dietaryEnergyConsumed: .sharingAuthorized,
                .dietarySodium: .sharingAuthorized
            ],
            readVisibility: .unverifiable
        )
        precondition(state.allRequestedWritesAuthorized)

        let denied = HealthAuthorizationState(
            healthDataAvailable: true,
            writeStatusByIdentifier: [
                .dietaryEnergyConsumed: .sharingAuthorized,
                .dietarySodium: .sharingDenied
            ],
            readVisibility: .unverifiable
        )
        precondition(!denied.allRequestedWritesAuthorized)

        let draft = HealthSampleDraft(
            typeIdentifier: .dietarySodium,
            value: 1200,
            unit: .milligram,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 3600),
            externalID: "test",
            wasUserEntered: true,
            stringMetadata: [:]
        )
        precondition(draft.typeIdentifier == .dietarySodium)
        print("TASK 4 PORTABLE AUTHORIZATION MODEL: PASS")
    }
}
