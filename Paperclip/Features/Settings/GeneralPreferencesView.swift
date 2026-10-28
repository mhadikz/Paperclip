import SwiftUI

struct GeneralPreferencesView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var settingsViewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Shortcut") {
                LabeledContent("Open History") {
                    ShortcutRecorderView(
                        current: settings.hotKey,
                        onRecord: { settingsViewModel.applyHotKey($0) },
                        onReset: { settingsViewModel.resetHotKey() }
                    )
                }
                if let error = settingsViewModel.hotKeyError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(AppTheme.caption)
                        .foregroundStyle(AppPalette.danger)
                }
                Text("Works everywhere, without Accessibility access. ⇧⌘V is also “Paste and Match Style” in some apps; pick another combination if you rely on that.")
                    .font(AppTheme.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pasting") {
                Toggle("Paste into the frontmost app after choosing a clip", isOn: $settings.pasteAndEnter)
                HStack(spacing: AppTheme.spaceS) {
                    Image(systemName: settingsViewModel.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(settingsViewModel.accessibilityGranted ? AppPalette.controlOn : AppPalette.danger)
                    Text(settingsViewModel.accessibilityGranted
                         ? "Accessibility access granted."
                         : "Accessibility access is needed to press ⌘V for you. Until then, choosing a clip only copies it.")
                        .font(AppTheme.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !settingsViewModel.accessibilityGranted {
                        Button("Open System Settings") {
                            settingsViewModel.requestAccessibility()
                            settingsViewModel.openAccessibilitySettings()
                        }
                        .appGlassButton()
                    }
                }
                Toggle("Keep rich text formatting (bold, links, colors)", isOn: $settings.captureRichText)
            }

            Section("History") {
                LabeledContent("Remember") {
                    HStack(spacing: AppTheme.spaceXS) {
                        TextField("", value: $settings.rememberCount, format: .number)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $settings.rememberCount, in: AppSettings.Limits.minRemember...AppSettings.Limits.maxRemember, step: 100)
                            .labelsHidden()
                        Text("clips")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Show in menu bar") {
                    HStack(spacing: AppTheme.spaceXS) {
                        TextField("", value: $settings.displayCount, format: .number)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $settings.displayCount, in: AppSettings.Limits.minDisplay...AppSettings.Limits.maxDisplay)
                            .labelsHidden()
                        Text("clips")
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Record clipboard history", isOn: $settings.recordHistory)
                Toggle("Ask before deleting", isOn: $settings.confirmBeforeDeleting)
                Text("Pinned and favorite clips are never trimmed.")
                    .font(AppTheme.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Open Paperclip at login", isOn: $settings.launchAtLogin)
                if !settingsViewModel.loginItemStatus.isEmpty {
                    HStack {
                        Text(settingsViewModel.loginItemStatus)
                            .font(AppTheme.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if settingsViewModel.loginItemStatus.contains("approval") {
                            Button("Open Login Items") { settingsViewModel.openLoginItemsSettings() }
                                .appGlassButton()
                        }
                    }
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: AppTheme.spaceS) {
                    LiquidGlassPreview()
                    Slider(value: $settings.glassTintAmount, in: 0...1)
                        .tint(AppPalette.controlOn)
                    HStack {
                        Text("Clear")
                        Spacer()
                        Text("\(Int(settings.glassTintAmount * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(AppPalette.brand)
                        Spacer()
                        Text("Tinted")
                    }
                    .font(AppTheme.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Privacy") {
                Toggle("Skip likely passwords, keys and card numbers", isOn: $settings.skipSensitiveContent)
                Toggle("Hide the History window from screen sharing", isOn: $settings.hideFromScreenSharing)
                Text("Password managers that mark their copies as concealed are always skipped. Add other apps under Ignored Apps.")
                    .font(AppTheme.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                LabeledContent("On this Mac") {
                    Text(storageText)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Everything is stored locally in Application Support. Nothing is uploaded.")
                        .font(AppTheme.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show in Finder") { settingsViewModel.revealDataFolder() }
                        .appGlassButton()
                }
            }
        }
        .appPreferencesChrome()
        .onAppear { settingsViewModel.refreshAll() }
    }

    private var storageText: String {
        let s = settingsViewModel.storageSummary
        var parts = ["\(s.clipCount.formatted()) clip\(s.clipCount == 1 ? "" : "s")"]
        if s.imageCount > 0 { parts.append("\(s.imageCount.formatted()) image\(s.imageCount == 1 ? "" : "s")") }
        parts.append(ByteCountText.string(s.byteCount))
        return parts.joined(separator: " · ")
    }
}
