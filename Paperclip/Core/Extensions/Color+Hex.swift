import SwiftUI
import AppKit

extension Color {
    init?(hex: String) {
        guard let ns = NSColor(hex: hex) else { return nil }
        self.init(nsColor: ns)
    }

    /// Resolves against the current AppKit appearance (Light / Dark / System).
    static func adaptive(
        lightHex: String,
        lightAlpha: CGFloat = 1,
        darkHex: String,
        darkAlpha: CGFloat = 1
    ) -> Color {
        Color(nsColor: NSColor.adaptive(
            lightHex: lightHex,
            lightAlpha: lightAlpha,
            darkHex: darkHex,
            darkAlpha: darkAlpha
        ))
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let int = UInt64(value, radix: 16) else { return nil }
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8) & 0xFF) / 255
        let b = CGFloat(int & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    static func adaptive(
        lightHex: String,
        lightAlpha: CGFloat = 1,
        darkHex: String,
        darkAlpha: CGFloat = 1
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = dark ? darkHex : lightHex
            let alpha = dark ? darkAlpha : lightAlpha
            let base = NSColor(hex: hex) ?? (dark ? .black : .white)
            return base.withAlphaComponent(alpha)
        }
    }
}
