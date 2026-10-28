import SwiftUI

struct AIMemoryView: View {
    @EnvironmentObject private var viewModel: AIMemoryViewModel
    @EnvironmentObject private var clipboardViewModel: ClipboardViewModel
    @EnvironmentObject private var searchViewModel: SearchViewModel
    @EnvironmentObject private var thumbnails: ThumbnailStore
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: AppSettings

    @ViewState private var showingDetail = false

    private var hasQuery: Bool {
        !appState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var listedClips: [ClipItem] {
        if hasQuery {
            return searchViewModel.results.map(\.clip)
        }
        return appState.navigationMode == .favorites ? viewModel.favoriteClips : viewModel.clips
    }

    var body: some View {
        Group {
            if showingDetail, let clip = viewModel.selectedClip {
                detailStack(clip)
            } else {
                resultsList
            }
        }
        .onChange(of: appState.navigationMode) { _, _ in showingDetail = false }
        .onChange(of: appState.searchText) { _, _ in showingDetail = false }
        .onChange(of: appState.historyPresentationCount) { _, _ in showingDetail = false }
        .background(
            HiddenShortcut(key: "y", modifiers: .command) {
                if viewModel.selectedClip != nil { showingDetail.toggle() }
            }
        )
        .background(
            HiddenShortcut(key: .downArrow) { moveSelection(by: 1) }
        )
        .background(
            HiddenShortcut(key: .upArrow) { moveSelection(by: -1) }
        )
    }

    private func moveSelection(by offset: Int) {
        let items = listedClips
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == appState.selectedClipID } ?? -1
        let next = min(max(index + offset, 0), items.count - 1)
        viewModel.selectMemory(items[next].id)
    }

    private func detailStack(_ clip: ClipItem) -> some View {
        VStack(spacing: 0) {
            Button {
                showingDetail = false
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(AppTheme.calloutMedium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("[", modifiers: .command)
            .padding(.horizontal, AppTheme.spaceL)
            .padding(.bottom, AppTheme.spaceS)
            MemoryDetailView(clip: clip)
        }
        .onExitCommand { showingDetail = false }
    }

    @ViewBuilder
    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !settings.aiFeaturesEnabled {
                Text("AI features are off. Keyword search still works over your history.")
                    .font(AppTheme.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.spaceL)
                    .padding(.bottom, AppTheme.spaceS)
            }

            if listedClips.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: AppTheme.spaceS) {
                            if hasQuery {
                                ForEach(searchViewModel.results) { result in
                                    memoryCard(result.clip, reason: result.reason)
                                        .id(result.clip.id)
                                }
                            } else {
                                ForEach(TimelineGrouping.group(listedClips)) { group in
                                    Text(group.title)
                                        .font(AppTheme.captionMedium)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, AppTheme.spaceXXS)
                                    ForEach(group.items) { clip in
                                        memoryCard(clip, reason: nil)
                                            .id(clip.id)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.spaceL)
                        .padding(.bottom, AppTheme.spaceM)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: appState.selectedClipID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }

    private func memoryCard(_ clip: ClipItem, reason: String?) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceXXS) {
            ClipCardView(
                clip: clip,
                metadata: viewModel.metadata(for: clip),
                pinboards: clipboardViewModel.pinboards(containing: clip),
                thumbnail: thumbnails.image(for: clip),
                isFavorite: viewModel.metadata(for: clip)?.isFavorite == true,
                isSelected: appState.selectedClipID == clip.id,
                onSelect: {
                    viewModel.selectMemory(clip.id)
                    showingDetail = true
                },
                onCopy: { viewModel.copyOnly(clip) },
                onPaste: { plain in viewModel.paste(clip, plainText: plain) },
                onPinboardTap: { board in
                    appState.navigationMode = .clipboard
                    appState.selectedPinboardID = board.id
                    showingDetail = false
                }
            )
            if let reason, !reason.isEmpty {
                Text("Matched: \(reason)")
                    .font(AppTheme.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, AppTheme.spaceS)
            }
        }
        .contextMenu {
            Button("Paste") { viewModel.paste(clip) }
            Button("Copy") { viewModel.copyOnly(clip) }
            Button("Details") {
                viewModel.selectMemory(clip.id)
                showingDetail = true
            }
            Button(viewModel.metadata(for: clip)?.isFavorite == true ? "Remove from Favorites" : "Add to Favorites") {
                viewModel.toggleFavorite(clip)
            }
            Divider()
            Button("Delete", role: .destructive) {
                clipboardViewModel.delete([clip])
            }
        }
    }

    private var emptyState: some View {
        AppEmptyState(
            systemImage: appState.navigationMode == .favorites ? "star" : (hasQuery ? "magnifyingglass" : "brain.head.profile"),
            title: appState.navigationMode == .favorites ? "No favorites yet" : (hasQuery ? "No matches" : "Search your clipboard memory"),
            subtitle: appState.navigationMode == .favorites
                ? "Mark a clip as a favorite from its context menu to keep it here. Favorites are never trimmed."
                : (hasQuery ? "Try different words, or mention a type, app, or time, like “link from Safari yesterday”."
                   : "Try “the GitHub link about authentication” or “docker command from last week”.")
        )
    }
}
