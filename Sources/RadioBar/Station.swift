import SwiftUI

struct Station: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var url: String
    var colorHex: String
    var hotkeyConfig: HotkeyConfig?

    init(id: UUID = UUID(), name: String, url: String,
         colorHex: String = "#007AFF", hotkeyConfig: HotkeyConfig? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.colorHex = colorHex
        self.hotkeyConfig = hotkeyConfig
    }

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    var nsColor: NSColor {
        NSColor(hex: colorHex) ?? .systemBlue
    }
}

// MARK: – Color hex helpers

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6 else { return nil }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >>  8) & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6 else { return nil }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            srgbRed:   CGFloat((value >> 16) & 0xFF) / 255,
            green:     CGFloat((value >>  8) & 0xFF) / 255,
            blue:      CGFloat( value        & 0xFF) / 255,
            alpha:     1
        )
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#007AFF" }
        return String(format: "#%02X%02X%02X",
                      Int(c.redComponent   * 255),
                      Int(c.greenComponent * 255),
                      Int(c.blueComponent  * 255))
    }
}
