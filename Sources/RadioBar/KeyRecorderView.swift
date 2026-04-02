import SwiftUI
import AppKit

// MARK: – Controller (class so the NSEvent monitor closure has stable reference semantics)

@MainActor
final class KeyRecorderController: ObservableObject {
    @Published var isRecording = false
    private var monitor: Any?

    func start(completion: @escaping (HotkeyConfig) -> Void) {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // Escape → cancel
            if event.keyCode == 53 {
                Task { @MainActor in self.stop() }
                return nil
            }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isFnKey = (96...121).contains(Int(event.keyCode))

            // Accept: modifier + any key, OR bare function key
            guard !mods.isEmpty || isFnKey else { return event }

            let cfg = HotkeyConfig(
                keyCode:   Int(event.keyCode),
                modifiers: Int(mods.rawValue),
                isEnabled: true
            )
            Task { @MainActor in
                completion(cfg)
                self.stop()
            }
            return nil   // Consume the event
        }
    }

    func stop() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// MARK: – SwiftUI view

struct KeyRecorderButton: View {
    @Binding var config: HotkeyConfig
    var onUpdate: (HotkeyConfig) -> Void

    @StateObject private var ctrl = KeyRecorderController()

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if ctrl.isRecording { ctrl.stop() } else {
                    ctrl.start { new in
                        config = new
                        onUpdate(new)
                    }
                }
            } label: {
                Text(label)
                    .font(.system(size: 12,
                                  design: ctrl.isRecording ? .default : .monospaced))
                    .frame(minWidth: 160, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(ctrl.isRecording ? .accentColor : nil)

            if config.isEnabled && !ctrl.isRecording {
                Button {
                    config = .disabled
                    onUpdate(.disabled)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Tastenkürzel entfernen")
            }
        }
        .onDisappear { ctrl.stop() }
    }

    private var label: String {
        if ctrl.isRecording { return "Taste drücken … (Esc = Abbrechen)" }
        return config.isEnabled ? config.displayString : "Nicht gesetzt – Klicken zum Aufnehmen"
    }
}
