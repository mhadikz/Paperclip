import WidgetKit
import SwiftUI
import AppIntents

@main
struct PaperclipWidgets: WidgetBundle {
    var body: some Widget {
        ClipboardHistoryWidget()
    }
}

struct ClipboardHistoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: ClipboardWidgetProvider()) { entry in
            ClipboardWidgetView(entry: entry)
        }
        .configurationDisplayName("Clipboard History")
        .description("Your most recent clips. Tap Copy to put one back on the clipboard; tap the header to open History.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ClipboardWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct ClipboardWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClipboardWidgetEntry {
        ClipboardWidgetEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (ClipboardWidgetEntry) -> Void) {
        completion(ClipboardWidgetEntry(date: Date(), snapshot: context.isPreview ? .sample : .load()))
    }

    /// The host app reloads timelines whenever history changes, and relative timestamps
    /// update on their own, so a slow fallback refresh is enough.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ClipboardWidgetEntry>) -> Void) {
        let entry = ClipboardWidgetEntry(date: Date(), snapshot: .load())
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

private enum WidgetPalette {
    static let midnight = Color(red: 0 / 255, green: 8 / 255, blue: 20 / 255)
    static let navyDeep = Color(red: 0 / 255, green: 29 / 255, blue: 61 / 255)
    static let navy = Color(red: 0 / 255, green: 53 / 255, blue: 102 / 255)
    static let gold = Color(red: 1, green: 195 / 255, blue: 0)
    static let goldBright = Color(red: 1, green: 214 / 255, blue: 10 / 255)
    static let white = Color.white

    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? midnight.opacity(0.94) : white.opacity(0.94)
    }

    static func primary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? white : midnight
    }

    static func muted(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? white.opacity(0.55) : navy.opacity(0.72)
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? goldBright : gold
    }
}

struct ClipboardWidgetView: View {
    var entry: ClipboardWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var systemScheme

    private var scheme: ColorScheme {
        switch entry.snapshot.appearance {
        case "light": return .light
        case "dark": return .dark
        default: return systemScheme
        }
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                small
            case .systemLarge:
                list(limit: 6)
            default:
                list(limit: 3)
            }
        }
        .environment(\.colorScheme, scheme)
        .containerBackground(for: .widget) {
            WidgetPalette.canvas(scheme)
        }
    }

    private var items: [WidgetSnapshot.Item] {
        entry.snapshot.items
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerButton
            if let item = items.first {
                copyRow(for: item, lineLimit: 4)
                Spacer(minLength: 0)
            } else {
                emptyButton
            }
        }
    }

    private func list(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            headerButton
            if items.isEmpty {
                emptyButton
                Spacer(minLength: 0)
            } else {
                ForEach(Array(items.prefix(limit))) { item in
                    copyRow(for: item, lineLimit: 1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var headerButton: some View {
        Link(destination: WidgetSnapshot.openHistoryURL()) {
            header
        }
    }

    private var emptyButton: some View {
        Link(destination: WidgetSnapshot.openHistoryURL()) {
            empty
        }
    }

    private func copyRow(for item: WidgetSnapshot.Item, lineLimit: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            itemContent(item, lineLimit: lineLimit)
            Spacer(minLength: 0)
            Button(intent: CopyClipIntent(clipID: item.id, copyText: item.copyText)) {
                Image(systemName: "square.on.square")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.accent(scheme))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy")
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "paperclip")
            Text("Paperclip")
                .fontWeight(.semibold)
            Spacer(minLength: 0)
            Text("\(items.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(WidgetPalette.muted(scheme))
        }
        .font(.caption)
        .foregroundStyle(WidgetPalette.accent(scheme))
    }

    private var empty: some View {
        Text("Copy something to see it here.")
            .font(.caption)
            .foregroundStyle(WidgetPalette.muted(scheme))
    }

    private func itemContent(_ item: WidgetSnapshot.Item, lineLimit: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol(for: item.contentType))
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent(for: item.contentType))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.primary(scheme))
                    .lineLimit(lineLimit)
                Text(item.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.muted(scheme))
            }
        }
    }

    private func symbol(for type: String) -> String {
        switch type {
        case "link": return "link"
        case "image": return "photo"
        case "file": return "doc"
        default: return "textformat"
        }
    }

    private func accent(for type: String) -> Color {
        switch type {
        case "link": return WidgetPalette.accent(scheme)
        case "image": return WidgetPalette.goldBright
        default: return scheme == .dark ? WidgetPalette.white.opacity(0.7) : WidgetPalette.navy
        }
    }
}
