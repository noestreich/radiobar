import SwiftUI

@main
struct RadioBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(delegate.store)
                .environmentObject(delegate.player)
                .environmentObject(delegate.hotkeys)
        }
    }
}
