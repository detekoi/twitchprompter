import SwiftUI
import AppKit

@main
struct TwitchPrompterApp: App {
    @StateObject private var viewModel = AppViewModel()

    init() {
        // Ensure this process is a regular app so its windows can receive key focus
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        // Bring to front
        application.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onAppear {
                    // Load the API key immediately when the app launches
                    viewModel.loadApiKey()
                }
        }
    }
}