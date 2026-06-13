import SwiftUI

@main
struct OppoPodsMacApp: App {
    @StateObject private var viewModel = EarbudsViewModel()

    var body: some Scene {
        WindowGroup("OppoPodsMac", id: "main") {
            MainWindowView()
                .environmentObject(viewModel)
                .onAppear {
                    viewModel.start()
                }
        }
        .defaultSize(width: 720, height: 520)

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
