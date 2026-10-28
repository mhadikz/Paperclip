import SwiftUI
import AppKit

struct IgnoredAppsPreferencesView: View {
    @EnvironmentObject private var settings: AppSettings
    @ViewState private var apps: [InstalledApp] = []
    @ViewState private var isLoading = true
    @ViewState private var filter = ""

    private var filteredApps: [InstalledApp] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppTheme.spaceS) {
                Image(systemName: "magnifyingglass")
                    .font(AppTheme.bodyMedium)
                    .foregroundStyle(AppPalette.brand)
                TextField("Filter apps", text: $filter)
                    .textFieldStyle(.plain)
                    .focusEffectDisabled()
            }
            .padding(.horizontal, AppTheme.spaceM)
            .padding(.vertical, AppTheme.spaceS)
            .appControlGlass()
            .padding(AppTheme.spaceS)

            if isLoading {
                ProgressView("Loading applications…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredApps) { app in
                    HStack(spacing: AppTheme.spaceS) {
                        Toggle("", isOn: Binding(
                            get: { settings.ignoredBundleIDs.contains(app.bundleIdentifier) },
                            set: { enabled in
                                if enabled {
                                    settings.ignoredBundleIDs.insert(app.bundleIdentifier)
                                } else {
                                    settings.ignoredBundleIDs.remove(app.bundleIdentifier)
                                }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.checkbox)

                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }

                        Text(app.name)
                            .lineLimit(1)
                    }
                }
                .appListChrome()
            }
        }
        .task {
            await loadApps()
        }
    }

    private func loadApps() async {
        isLoading = true
        let loaded = await Task.detached(priority: .userInitiated) {
            InstalledAppsService.loadApps()
        }.value
        apps = loaded
        isLoading = false
    }
}
