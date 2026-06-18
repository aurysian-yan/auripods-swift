import SwiftUI

@main
struct AuriBudsIOSApp: App {
    @StateObject private var viewModel = EarbudsViewModel()

    init() {
        BluetoothMonitor.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onAppear {
                    viewModel.start()
                }
        }
    }
}
