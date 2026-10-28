import SwiftUI
import AppKit

/// Click, press a key combination, done. Esc cancels; the reset button restores ⇧⌘V.
struct ShortcutRecorderView: View {
    let current: HotKeySpec
    let onRecord: (HotKeySpec) -> Void
    let onReset: () -> Void

    @ViewState private var isRecording = false
    @ViewState private var monitor: Any?

    var body: some View {
        HStack(spacing: AppTheme.spaceS) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                HStack(spacing: AppTheme.spaceXS) {
                    if isRecording {
                        Image(systemName: "record.circle")
                            .foregroundStyle(AppPalette.danger)
                        Text("Press keys…")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(current.displayString)
                            .font(AppTheme.keycap)
                    }
                }
                .frame(minWidth: 120)
                .padding(.horizontal, AppTheme.spaceM)
                .padding(.vertical, AppTheme.spaceXS)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .appControlGlass()
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusControl, style: .continuous)
                    .strokeBorder(isRecording ? AppPalette.brand : .clear, lineWidth: 1.5)
            )
            .accessibilityLabel(isRecording ? "Recording shortcut" : "Shortcut \(current.displayString)")

            if current != .default {
                Button("Reset") { onReset() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(AppTheme.caption)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { // Escape
            stopRecording()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = HotKeyModifiers(eventFlags: flags)
        let label = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines)
        let spec = HotKeySpec(
            keyCode: event.keyCode,
            modifiers: modifiers,
            keyLabel: (label?.isEmpty == false) ? label : nil
        )
        stopRecording()
        onRecord(spec)
    }
}
