import SwiftUI
import AppKit

/// An NSColorWell wrapped for SwiftUI that binds directly to a hex string.
struct NSColorPickerView: NSViewRepresentable {
    @Binding var colorHex: String

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell(style: .expanded)
        well.color = NSColor(hex: colorHex) ?? .systemBlue
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        let desired = NSColor(hex: colorHex) ?? .systemBlue
        if well.color != desired { well.color = desired }
    }

    func makeCoordinator() -> Coordinator { Coordinator(binding: $colorHex) }

    final class Coordinator: NSObject {
        var binding: Binding<String>
        init(binding: Binding<String>) { self.binding = binding }

        @objc func colorChanged(_ sender: NSColorWell) {
            binding.wrappedValue = sender.color.hexString
        }
    }
}
