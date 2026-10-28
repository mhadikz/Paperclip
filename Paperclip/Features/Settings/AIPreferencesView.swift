import SwiftUI

struct AIPreferencesView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var settingsViewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("AI Memory") {
                Toggle("Enable AI Memory", isOn: $settings.aiFeaturesEnabled)
                Toggle("Classify and tag new clips automatically", isOn: $settings.automaticAIProcessing)
                    .disabled(!settings.aiFeaturesEnabled)
                Toggle("Write summaries for long clips", isOn: $settings.automaticSummaries)
                    .disabled(!settings.aiFeaturesEnabled)
                Toggle("Suggest tags", isOn: $settings.automaticTags)
                    .disabled(!settings.aiFeaturesEnabled)
                Toggle("Understand natural-language searches", isOn: $settings.semanticSearch)
                    .disabled(!settings.aiFeaturesEnabled)
                Text("With AI off, Paperclip is a complete clipboard manager with keyword search. Nothing else changes.")
                    .font(AppTheme.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Apple Intelligence") {
                Toggle("Use Apple Foundation Models when available", isOn: $settings.useFoundationModels)
                    .disabled(!settings.aiFeaturesEnabled)
                HStack(spacing: AppTheme.spaceS) {
                    Image(systemName: settingsViewModel.isFoundationModelsAvailable ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(settingsViewModel.isFoundationModelsAvailable ? AppPalette.controlOn : Color.secondary)
                    Text(settingsViewModel.availabilityText)
                        .font(AppTheme.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Requires macOS 26 or later with Apple Intelligence turned on. Models run entirely on this Mac. Without them, fast local heuristics classify and tag clips.")
                    .font(AppTheme.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sensitive content") {
                Picker("When a copy looks like a secret", selection: $settings.sensitiveStoragePolicy) {
                    ForEach(SensitiveStoragePolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                Text(settings.sensitiveStoragePolicy.detail)
                    .font(AppTheme.caption)
                    .foregroundStyle(.secondary)
                Toggle("Allow the model to process sensitive content", isOn: $settings.processSensitiveContent)
                    .disabled(!settings.aiFeaturesEnabled)
            }

            Section("Maintenance") {
                HStack {
                    Button("Re-enrich all clips") { settingsViewModel.reprocessAllAI() }
                        .appGlassButton()
                        .disabled(!settings.aiFeaturesEnabled)
                    if settingsViewModel.aiPendingCount > 0 {
                        Text("\(settingsViewModel.aiPendingCount) waiting")
                            .font(AppTheme.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear AI metadata") { settingsViewModel.clearAIMetadata() }
                        .appDangerButton()
                }
                Text("Clearing AI metadata removes summaries, tags and favorites. Your clipboard history is untouched.")
                    .font(AppTheme.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .appPreferencesChrome()
        .task { await settingsViewModel.refreshAvailability() }
    }
}
