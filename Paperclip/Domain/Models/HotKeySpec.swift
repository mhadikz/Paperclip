import Foundation

/// Modifier keys for a global shortcut. Raw values are stable (persisted in UserDefaults).
struct HotKeyModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt8

    static let command = HotKeyModifiers(rawValue: 1 << 0)
    static let shift = HotKeyModifiers(rawValue: 1 << 1)
    static let option = HotKeyModifiers(rawValue: 1 << 2)
    static let control = HotKeyModifiers(rawValue: 1 << 3)

    /// Standard macOS glyph order: ⌃ ⌥ ⇧ ⌘
    var displayString: String {
        var parts = ""
        if contains(.control) { parts += "⌃" }
        if contains(.option) { parts += "⌥" }
        if contains(.shift) { parts += "⇧" }
        if contains(.command) { parts += "⌘" }
        return parts
    }
}

/// A global keyboard shortcut (virtual key code + modifiers). Layout-independent for
/// registration; `keyLabel` remembers what the user saw when recording it.
struct HotKeySpec: Codable, Hashable, Sendable {
    var keyCode: UInt16
    var modifiers: HotKeyModifiers
    /// Printable key captured from the keyboard layout at recording time (e.g. "V", "Space").
    var keyLabel: String?

    init(keyCode: UInt16, modifiers: HotKeyModifiers, keyLabel: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// ⇧⌘V — the same default as Paste.
    static let `default` = HotKeySpec(keyCode: 9, modifiers: [.command, .shift], keyLabel: "V")

    /// A usable global shortcut needs at least one "command-like" modifier so it does not
    /// swallow ordinary typing. Function keys are allowed on their own.
    var isValid: Bool {
        if Self.functionKeyCodes.contains(keyCode) { return true }
        return !modifiers.isDisjoint(with: [.command, .control, .option])
    }

    var displayString: String {
        modifiers.displayString + keyDisplay
    }

    var keyDisplay: String {
        if let name = Self.keyName(for: keyCode) { return name }
        if let keyLabel, !keyLabel.isEmpty { return keyLabel.uppercased() }
        return "Key \(keyCode)"
    }

    private static let functionKeyCodes: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113
    ]

    /// Virtual key codes (ANSI layout) → display names. Letters/digits fall back to `keyLabel`
    /// so non-US layouts still show what the user pressed.
    static func keyName(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 71: return "⌧"
        case 76: return "⌤"
        case 115: return "↖"
        case 116: return "⇞"
        case 117: return "⌦"
        case 119: return "↘"
        case 121: return "⇟"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        default: return nil
        }
    }
}
