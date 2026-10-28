import SwiftUI
import AppKit

/// Visual kind for History cards. Presentation-only — does not change stored `ClipContentType`.
enum ClipCardKind: String {
    case link
    case code
    case text
    case image
    case file

    var badgeTitle: String { rawValue }

    var systemImage: String {
        switch self {
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .text: return "textformat"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    var badgeForeground: Color {
        switch self {
        case .link: return AppPalette.link
        case .code: return AppPalette.code
        case .text: return AppPalette.text
        case .image: return AppPalette.image
        case .file: return AppPalette.file
        }
    }

    var badgeBackground: Color {
        badgeForeground.opacity(0.14)
    }

    var contentBackground: Color {
        badgeForeground.opacity(0.08)
    }

    static func resolve(clip: ClipItem, metadata: AIMemoryMetadata?) -> ClipCardKind {
        switch clip.contentType {
        case .link: return .link
        case .image: return .image
        case .file: return .file
        case .text:
            if metadata?.category == .url { return .link }
            if metadata?.category?.isCodeLike == true { return .code }
            if textLooksLikeCode(clip.cardExcerpt) { return .code }
            return .text
        }
    }

    private static func textLooksLikeCode(_ text: String) -> Bool {
        let signals = ["func ", "import ", "package ", "def ", "const ", "let ", "var ", "=>", "};", "npm ", "docker ", "SELECT ", "{\n"]
        return signals.filter { text.contains($0) }.count >= 2
    }
}

enum ShortRelativeTime {
    static func string(from date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 10 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

enum ByteCountText {
    static func string(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

extension HotKeySpec {
    /// SwiftUI shortcut for menus. Nil for keys SwiftUI cannot express.
    var keyboardShortcut: KeyboardShortcut? {
        var modifiers: EventModifiers = []
        if self.modifiers.contains(.command) { modifiers.insert(.command) }
        if self.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if self.modifiers.contains(.option) { modifiers.insert(.option) }
        if self.modifiers.contains(.control) { modifiers.insert(.control) }

        let key: KeyEquivalent?
        switch keyCode {
        case 36: key = .return
        case 48: key = .tab
        case 49: key = .space
        case 51: key = .delete
        case 53: key = .escape
        case 123: key = .leftArrow
        case 124: key = .rightArrow
        case 125: key = .downArrow
        case 126: key = .upArrow
        default:
            if let label = keyLabel?.lowercased(), label.count == 1, let ch = label.first {
                key = KeyEquivalent(ch)
            } else {
                key = nil
            }
        }
        guard let key else { return nil }
        return KeyboardShortcut(key, modifiers: modifiers)
    }
}

struct ClipTypeBadge: View {
    let kind: ClipCardKind

    var body: some View {
        AppChip(
            title: kind.badgeTitle,
            systemImage: kind.systemImage,
            foreground: kind.badgeForeground,
            fill: kind.badgeBackground
        )
    }
}

struct PinboardBadge: View {
    let board: Pinboard

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(board.color)
                .frame(width: 6, height: 6)
            Text(board.name)
                .font(AppTheme.captionMedium)
                .lineLimit(1)
        }
        .foregroundStyle(board.color)
        .padding(.horizontal, AppTheme.chipPadH)
        .padding(.vertical, AppTheme.chipPadV)
        .background(Capsule().fill(board.color.opacity(0.14)))
        .overlay(Capsule().strokeBorder(board.color.opacity(0.35), lineWidth: 0.6))
    }
}

struct HistoryKeycap: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(AppTheme.keycap)
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppTheme.keycapPadH)
            .padding(.vertical, AppTheme.keycapPadV)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusKeycap, style: .continuous)
                    .fill(AppPalette.keycapFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusKeycap, style: .continuous)
                    .strokeBorder(AppPalette.stroke, lineWidth: 0.6)
            )
    }
}

struct HistoryShortcutHint: View {
    let keys: [String]
    var label: String? = nil

    var body: some View {
        HStack(spacing: AppTheme.spaceXXS) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                HistoryKeycap(symbol: key)
            }
            if let label {
                Text(label)
                    .font(AppTheme.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct HistorySearchField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        HStack(spacing: AppTheme.spaceS) {
            Image(systemName: "magnifyingglass")
                .font(AppTheme.bodyMedium)
                .foregroundStyle(AppPalette.brand)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .focusEffectDisabled()
                .accessibilityLabel("Search Clipboard and Memory")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AppTheme.spaceM)
        .padding(.vertical, AppTheme.spaceS)
        .appControlGlass()
    }
}

struct HistoryFilterChip: View {
    let title: String
    let onClear: () -> Void

    var body: some View {
        AppChip(title: title, onClear: onClear)
    }
}

/// Invisible button that only exists to own a keyboard shortcut.
struct HiddenShortcut: View {
    let key: KeyEquivalent
    var modifiers: EventModifiers = []
    let action: () -> Void

    var body: some View {
        Button(action: action) { EmptyView() }
            .keyboardShortcut(key, modifiers: modifiers)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }
}
