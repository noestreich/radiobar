import SwiftUI

@main
struct RadioBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Leerer Platzhalter – das echte Einstellungsfenster verwaltet AppDelegate
        // selbst via NSWindow, damit es aus jedem Kontext (Popover-Button,
        // Kontextmenü, Hotkey) zuverlässig geöffnet werden kann.
        Settings { EmptyView() }
            .commands {
                // Standard-"Settings…"-Menüpunkt (⌘,) durch unseren eigenen ersetzen,
                // der über NotificationCenter an AppDelegate weiterdelegiert.
                CommandGroup(replacing: .appSettings) {
                    Button("Einstellungen…") {
                        NotificationCenter.default.post(
                            name: .radioBarOpenSettings, object: nil)
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

extension Notification.Name {
    static let radioBarOpenSettings = Notification.Name("de.aketo.radiobar.openSettings")
}
