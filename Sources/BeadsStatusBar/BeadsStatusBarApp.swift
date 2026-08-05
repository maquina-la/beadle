import SwiftUI

@main
struct BeadsStatusBarApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(state)
        } label: {
            Label("\(state.openIssueCount)", systemImage: "circle.hexagongrid.fill")
                .accessibilityLabel("Beadle: \(state.openIssueCount) open issues")
                .task { state.startPolling() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(state)
        }

        #if DEBUG
        WindowGroup("Beadle", id: "readme-screenshot") {
            DashboardView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)
        #endif
    }
}
