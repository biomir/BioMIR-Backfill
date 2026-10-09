import SwiftUI

@main
struct BioMIRBackfillApp: App {
    @StateObject private var viewModel = ImportViewModel.makeLive()

    var body: some Scene {
        WindowGroup {
            ImportFlowView(viewModel: viewModel)
        }
    }
}
