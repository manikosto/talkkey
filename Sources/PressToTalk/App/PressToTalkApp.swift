import SwiftUI

@main
struct PressToTalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(appState: AppState.shared)
        }
    }
}
