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
                .accessibilityLabel("Beads: \(state.openIssueCount) open issues")
                .task { state.startPolling() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}
