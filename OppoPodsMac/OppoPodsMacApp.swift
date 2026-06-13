import SwiftUI

@main
struct OppoPodsMacApp: App {
    @StateObject private var viewModel = EarbudsViewModel()

    init() {
        BluetoothMonitor.shared.start()

        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            ConnectionPopupWindowController.shared.showConnectedIfNeeded(
                deviceName: "OPPO Enco Test",
                batteryLevel: 88
            )
        }
        #endif
    }

    var body: some Scene {
        WindowGroup("", id: "main") {
            MainWindowView()
                .environmentObject(viewModel)
                .onAppear {
                    viewModel.start()
                }
        }
        .defaultSize(width: 768, height: 720)

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(viewModel)
                .onAppear {
                    viewModel.start()
                }
        } label: {
            Image("oppobuds.bud.large")
                .font(.system(size: 24, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .accessibilityLabel("OppoPodsMac")
        }
        .menuBarExtraStyle(.window)
    }
}
