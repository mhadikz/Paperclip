import SwiftUI
import AppKit

struct ClipsManagementPreferencesView: View {
    @EnvironmentObject private var clipboardViewModel: ClipboardViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @ViewState private var selection = Set<ClipItem.ID>()
    @ViewState private var filter = ""

    private var rows: [ClipItem] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return clipboardViewModel.clips }
        return clipboardViewModel.clips.filter { $0.searchBlob.contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppTheme.spaceS) {
                Image(systemName: "magnifyingglass")
                    .font(AppTheme.bodyMedium)
                    .foregroundStyle(AppPalette.brand)
                TextField("Filter clips", text: $filter)
                    .textFieldStyle(.plain)
                    .focusEffectDisabled()
            }
            .padding(.horizontal, AppTheme.spaceM)
            .padding(.vertical, AppTheme.spaceS)
            .appControlGlass()
            .padding(AppTheme.spaceS)

            if rows.isEmpty {
                AppEmptyState(systemImage: "doc.on.clipboard", title: filter.isEmpty ? "No clips" : "No matches", subtitle: filter.isEmpty ? "Your history is empty." : "Try another filter.")
            } else {
                List(rows, selection: $selection) { clip in
                    HStack(spacing: AppTheme.spaceS) {
                        Image(systemName: clip.contentType.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(clip.preview)
                            .lineLimit(1)
                        Spacer()
                        if clipboardViewModel.isFavorite(clip) {
                            Image(systemName: "star.fill")
                                .font(AppTheme.caption2)
                                .foregroundStyle(AppPalette.brand)
                        }
                        if let app = clip.sourceAppName {
                            Text(app)
                                .font(AppTheme.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text(ShortRelativeTime.string(from: clip.createdAt))
                            .font(AppTheme.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 64, alignment: .trailing)
                    }
                    .tag(clip.id)
                }
                .appListChrome()
            }

            HStack {
                Text("\(rows.count.formatted()) clip\(rows.count == 1 ? "" : "s")\(selection.isEmpty ? "" : " · \(selection.count) selected")")
                    .font(AppTheme.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Delete All…") { deleteAll() }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppPalette.danger)
                    .disabled(clipboardViewModel.clips.isEmpty)
                Button("Delete Selected") { deleteSelected() }
                    .disabled(selection.isEmpty)
                    .appDangerButton()
            }
            .padding(AppTheme.spaceM)
            .appControlGlass()
            .padding(AppTheme.spaceS)
        }
    }

    private func deleteSelected() {
        let items = clipboardViewModel.clips.filter { selection.contains($0.id) }
        guard !items.isEmpty else { return }
        clipboardViewModel.delete(items)
        selection.removeAll()
    }

    private func deleteAll() {
        clipboardViewModel.confirmDeleteAllIfNeeded()
        selection.removeAll()
    }
}
