import SwiftUI

@main
struct PaperclipApp: App {
    @ObservedObject private var container = DependencyContainer.shared

    init() {
        DependencyContainer.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(container)
                .environmentObject(container.clipboardViewModel)
                .environmentObject(container.settings)
                .environmentObject(container.appState)
                .onOpenURL { container.handleOpenURL($0) }
        } label: {
            // No `@EnvironmentObject` here: MenuBarExtra evaluates its label before any parent
            // environment exists and the agent would crash (the paperclip "vanishes").
            MenuBarLabel(settings: container.settings)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Template paperclip; a badge appears while recording is paused.
private struct MenuBarLabel: View {
    @ObservedObject var settings: AppSettings

    private static let pausedSymbol: String = {
        NSImage(systemSymbolName: "paperclip.badge.ellipsis", accessibilityDescription: nil) != nil
            ? "paperclip.badge.ellipsis"
            : "paperclip"
    }()

    var body: some View {
        Image(systemName: settings.recordHistory ? "paperclip" : Self.pausedSymbol)
            .renderingMode(.template)
            .accessibilityLabel(settings.recordHistory ? "Paperclip" : "Paperclip (recording paused)")
    }
}
