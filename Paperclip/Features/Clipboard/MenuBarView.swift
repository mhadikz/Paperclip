import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var viewModel: ClipboardViewModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        openHistoryButton

        Text(settings.recordHistory ? "Choose a clip to copy it" : "Recording paused")
            .foregroundStyle(.secondary)

        Divider()

        let clips = viewModel.displayedClips
        if clips.isEmpty {
            Text("No clips yet")
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                clipButton(clip, index: index)
            }
        }

        if !viewModel.stackClips.isEmpty {
            Divider()
            Button("Paste Next from Stack (\(viewModel.stackClips.count))") {
                viewModel.pasteNextFromStack()
            }
            Button("Clear Paste Stack") {
                viewModel.clearStack()
            }
        }

        Divider()

        Button(settings.recordHistory ? "Pause Recording" : "Resume Recording") {
            settings.recordHistory.toggle()
        }

        Button("Delete All History…") {
            viewModel.confirmDeleteAllIfNeeded()
        }
        .disabled(viewModel.clips.isEmpty)

        Button("Settings…") {
            viewModel.showPreferences()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Paperclip") {
            viewModel.quit()
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    @ViewBuilder
    private var openHistoryButton: some View {
        let button = Button("Open Clipboard History") {
            viewModel.showHistory()
        }
        if let shortcut = settings.hotKey.keyboardShortcut {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }

    @ViewBuilder
    private func clipButton(_ clip: ClipItem, index: Int) -> some View {
        let kind = ClipCardKind.resolve(clip: clip, metadata: viewModel.metadata(for: clip))
        let button = Button {
            viewModel.pasteFromMenu(clip)
        } label: {
            Label(clip.preview, systemImage: kind.systemImage)
        }

        if index < 10 {
            button.keyboardShortcut(KeyEquivalent(Array("0123456789")[index]), modifiers: .command)
        } else {
            button
        }
    }
}
