import SwiftUI

@main
struct BeadsStatusBarApp: App {
    static let doltHealthWindowID = "dolt-health"

    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(state)
        } label: {
            Label {
                Text("\(state.openIssueCount)")
            } icon: {
                Image(nsImage: BeadleMark.templateImage())
            }
                .accessibilityLabel("Beadle: \(state.openIssueCount) open issues")
                .task { state.startPolling() }
        }
        .menuBarExtraStyle(.window)

        // Its own window, not a sheet on the menu bar panel. That panel is
        // non-activating and closes as soon as it resigns key, so a sheet
        // hanging off it vanished the moment any of its buttons were clicked.
        Window("Dolt Health", id: Self.doltHealthWindowID) {
            DoltHealthView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)

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
