import SwiftUI
import AppKit

struct ClipboardView: View {
    @EnvironmentObject private var viewModel: ClipboardViewModel
    @EnvironmentObject private var aiViewModel: AIMemoryViewModel
    @EnvironmentObject private var searchViewModel: SearchViewModel
    @EnvironmentObject private var thumbnails: ThumbnailStore
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: AppSettings

    @ViewState private var newBoardName = ""
    @ViewState private var showingNewBoard = false
    @ViewState private var showingPinboardManager = false
    @ViewState private var boardBeingRenamed: Pinboard?
    @ViewState private var clipBeingRenamed: ClipItem?
    @ViewState private var renameDraft = ""
    @FocusState private var searchFocused: Bool

    private var clips: [ClipItem] { viewModel.visibleClips }

    var body: some View {
        VStack(spacing: 0) {
            header
            if appState.previewClipID == nil {
                search
                activeFilters
            }
            mainContent
            footer
        }
        .appWindowFill()
        .appWindowContainer()
        .appBrandChrome()
        .background(keyboardShortcuts)
        .onAppear {
            searchFocused = true
            viewModel.selectFirstIfNeeded()
        }
        .onChange(of: appState.historyPresentationCount) { _, _ in
            searchFocused = true
            viewModel.selectFirstIfNeeded()
            if appState.navigationMode != .clipboard {
                searchViewModel.refresh()
            }
        }
        .onExitCommand(perform: handleEscape)
        .onChange(of: appState.selectedMemoryID) { _, newValue in
            if let newValue {
                appState.selectedClipID = newValue
            }
        }
        .alert("New Pinboard", isPresented: $showingNewBoard) {
            TextField("Name", text: $newBoardName)
            Button("Create") {
                viewModel.createPinboard(name: newBoardName)
                newBoardName = ""
            }
            Button("Cancel", role: .cancel) { newBoardName = "" }
        }
        .alert("Rename Pinboard", isPresented: Binding(
            get: { boardBeingRenamed != nil },
            set: { if !$0 { boardBeingRenamed = nil } }
        )) {
            TextField("Name", text: $renameDraft)
            Button("Save") {
                if let board = boardBeingRenamed {
                    viewModel.renamePinboard(board, name: renameDraft)
                }
                boardBeingRenamed = nil
            }
            Button("Cancel", role: .cancel) { boardBeingRenamed = nil }
        }
        .alert("Rename Clip", isPresented: Binding(
            get: { clipBeingRenamed != nil },
            set: { if !$0 { clipBeingRenamed = nil } }
        )) {
            TextField("Title", text: $renameDraft)
            Button("Save") {
                if let clip = clipBeingRenamed {
                    viewModel.rename(clip, title: renameDraft)
                }
                clipBeingRenamed = nil
            }
            Button("Cancel", role: .cancel) { clipBeingRenamed = nil }
        } message: {
            Text("A title is shown instead of the first line. Leave it empty to remove the title.")
        }
        .sheet(isPresented: $showingPinboardManager) {
            PinboardManagerView()
                .environmentObject(viewModel)
                .environmentObject(appState)
                .environmentObject(settings)
                .frame(width: 400, height: 440)
                .appWindowFill()
                .appFloatingGlass()
                .appBrandChrome()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: AppTheme.spaceS) {
            Menu {
                ForEach(HistoryNavigationMode.allCases) { mode in
                    Button {
                        appState.navigationMode = mode
                        appState.previewClipID = nil
                    } label: {
                        if appState.navigationMode == mode {
                            Label(mode.windowTitle, systemImage: "checkmark")
                        } else {
                            Text(mode.windowTitle)
                        }
                    }
                }
            } label: {
                HStack(spacing: AppTheme.spaceXS) {
                    Image(systemName: appState.navigationMode.systemImage)
                        .foregroundStyle(AppPalette.brand)
                    Text(appState.navigationMode.windowTitle)
                        .font(AppTheme.title)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(AppTheme.captionMedium)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .accessibilityLabel("Mode: \(appState.navigationMode.windowTitle)")

            if !settings.recordHistory {
                AppChip(title: "Paused", systemImage: "pause.fill", foreground: AppPalette.danger, fill: AppPalette.danger.opacity(0.12))
                    .help("Recording is paused")
            }

            Spacer(minLength: AppTheme.spaceS)

            AppGlassCluster(spacing: AppTheme.spaceS) {
                Menu {
                    overflowMenu
                } label: {
                    Image(systemName: "ellipsis")
                        .font(AppTheme.bodyMedium)
                        .foregroundStyle(.secondary)
                        .frame(width: AppTheme.iconButton, height: AppTheme.iconButton)
                        .contentShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .appIconGlass()
                .help("More")
            }
        }
        .padding(.leading, AppTheme.titlebarLeading)
        .padding(.trailing, AppTheme.spaceL)
        .padding(.top, AppTheme.spaceS)
        .padding(.bottom, AppTheme.spaceM)
    }

    @ViewBuilder
    private var overflowMenu: some View {
        if appState.navigationMode == .clipboard {
            Menu("Pinboard") {
                Button {
                    appState.selectedPinboardID = nil
                } label: {
                    if appState.selectedPinboardID == nil { Label("All History", systemImage: "checkmark") } else { Text("All History") }
                }
                ForEach(viewModel.pinboards) { board in
                    Button {
                        appState.selectedPinboardID = board.id
                    } label: {
                        if appState.selectedPinboardID == board.id { Label(board.name, systemImage: "checkmark") } else { Text(board.name) }
                    }
                }
                Divider()
                Button("New Pinboard…") { showingNewBoard = true }
                Button("Manage Pinboards…") { showingPinboardManager = true }
            }
            Menu("Show") {
                Button {
                    appState.filterType = nil
                } label: {
                    if appState.filterType == nil { Label("All Types", systemImage: "checkmark") } else { Text("All Types") }
                }
                ForEach(ClipContentType.allCases) { type in
                    Button {
                        appState.filterType = type
                    } label: {
                        if appState.filterType == type { Label(type.title, systemImage: "checkmark") } else { Text(type.title) }
                    }
                }
            }
            Divider()
        }
        Button(settings.recordHistory ? "Pause Recording" : "Resume Recording") {
            settings.recordHistory.toggle()
        }
        if !viewModel.stack.isEmpty {
            Button("Paste Next from Stack (\(viewModel.stack.count))") {
                viewModel.pasteNextFromStack()
            }
            Button("Clear Paste Stack") { viewModel.clearStack() }
        }
        Divider()
        Button("Delete All History…") {
            viewModel.confirmDeleteAllIfNeeded()
        }
        .disabled(viewModel.clips.isEmpty)
        Divider()
        Button("Settings…") { viewModel.showPreferences() }
    }

    private var search: some View {
        HistorySearchField(
            placeholder: appState.navigationMode == .clipboard
                ? "Search history"
                : "Ask your memory, e.g. “docker command from last week”",
            text: $appState.searchText,
            isFocused: $searchFocused
        )
        .padding(.horizontal, AppTheme.spaceL)
        .padding(.bottom, AppTheme.spaceM)
    }

    @ViewBuilder
    private var activeFilters: some View {
        let board = viewModel.activePinboard
        let type = appState.filterType
        if board != nil || type != nil {
            HStack(spacing: AppTheme.spaceS) {
                if let board {
                    HistoryFilterChip(title: board.name) {
                        appState.selectedPinboardID = nil
                    }
                    .contextMenu {
                        Button("Rename…") {
                            renameDraft = board.name
                            boardBeingRenamed = board
                        }
                        Button("Manage Pinboards…") { showingPinboardManager = true }
                        Divider()
                        Button("Delete Pinboard", role: .destructive) {
                            viewModel.confirmDeletePinboard(board)
                        }
                    }
                }
                if let type {
                    HistoryFilterChip(title: type.title) {
                        appState.filterType = nil
                    }
                }
                Spacer()
            }
            .padding(.horizontal, AppTheme.spaceL)
            .padding(.bottom, AppTheme.spaceS)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var mainContent: some View {
        if appState.navigationMode == .clipboard, let preview = viewModel.previewClip {
            ClipPreviewView(clip: preview) { viewModel.closePreview() }
        } else {
            switch appState.navigationMode {
            case .clipboard:
                clipBrowser
            case .aiMemory, .favorites:
                AIMemoryView()
            }
        }
    }

    @ViewBuilder
    private var clipBrowser: some View {
        if clips.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AppTheme.spaceS) {
                        ForEach(clips) { clip in
                            ClipCardView(
                                clip: clip,
                                metadata: viewModel.metadata(for: clip),
                                pinboards: viewModel.pinboards(containing: clip),
                                thumbnail: thumbnails.image(for: clip),
                                isFavorite: viewModel.isFavorite(clip),
                                isSelected: appState.selectedClipID == clip.id,
                                onSelect: { appState.selectedClipID = clip.id },
                                onCopy: { viewModel.copyOnly(clip) },
                                onPaste: { plain in viewModel.paste(clip, plainText: plain) },
                                onPinboardTap: { board in appState.selectedPinboardID = board.id }
                            )
                            .id(clip.id)
                            .contextMenu { clipContextMenu(clip) }
                        }
                    }
                    .padding(.horizontal, AppTheme.spaceL)
                    .padding(.bottom, AppTheme.spaceM)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: appState.selectedClipID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        AppEmptyState(
            systemImage: emptyIcon,
            title: emptyTitle,
            subtitle: emptySubtitle
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: AppTheme.spaceM) {
            Text(footerStatus)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if appState.navigationMode == .clipboard {
                if appState.previewClipID == nil {
                    HistoryShortcutHint(keys: ["↩"], label: viewModel.pastesIntoFrontmostApp ? "Paste" : "Copy")
                    HistoryShortcutHint(keys: ["⌘Y"], label: "Preview")
                } else {
                    HistoryShortcutHint(keys: ["⎋"], label: "Back")
                }
            } else {
                HistoryShortcutHint(keys: ["↩"], label: "Paste")
            }
        }
        .font(AppTheme.caption)
        .padding(.horizontal, AppTheme.spaceM)
        .padding(.vertical, AppTheme.spaceS)
        .appControlGlass()
        .padding(.horizontal, AppTheme.spaceL)
        .padding(.bottom, AppTheme.spaceM)
    }

    private var footerStatus: String {
        switch appState.navigationMode {
        case .aiMemory:
            if searchViewModel.isRefining { return "Refining with Apple Intelligence…" }
            return appState.searchText.isEmpty ? "On-device memory · nothing leaves this Mac" : "\(searchViewModel.results.count) result\(searchViewModel.results.count == 1 ? "" : "s")"
        case .favorites:
            let count = aiViewModel.favoriteClips.count
            return "\(count) favorite\(count == 1 ? "" : "s")"
        case .clipboard:
            let count = clips.count
            if let board = viewModel.activePinboard {
                return "\(count) item\(count == 1 ? "" : "s") in \(board.name)"
            }
            if !appState.searchText.isEmpty {
                return "\(count) match\(count == 1 ? "" : "es")"
            }
            return "\(count) item\(count == 1 ? "" : "s") in history"
        }
    }

    private var emptyIcon: String {
        if !appState.searchText.isEmpty { return "magnifyingglass" }
        if viewModel.activePinboard != nil { return "pin" }
        return "doc.on.clipboard"
    }

    private var emptyTitle: String {
        if !appState.searchText.isEmpty { return "No matches" }
        if viewModel.activePinboard != nil { return "Empty pinboard" }
        if !settings.recordHistory { return "Recording is paused" }
        return "Nothing copied yet"
    }

    private var emptySubtitle: String {
        if !appState.searchText.isEmpty { return "Try a different search or remove a filter." }
        if let board = viewModel.activePinboard {
            return "Pin clips to “\(board.name)” from a card’s context menu."
        }
        if !settings.recordHistory { return "Resume recording from the ••• menu to capture new clips." }
        return "Copy text, links, images, or files and they will appear here. Press \(viewModel.hotKeyDisplay) anytime to open this window."
    }

    // MARK: - Keyboard

    private var keyboardShortcuts: some View {
        Group {
            HiddenShortcut(key: .downArrow) { viewModel.moveSelection(by: 1) }
            HiddenShortcut(key: .upArrow) { viewModel.moveSelection(by: -1) }
            HiddenShortcut(key: .return) { pasteSelected(plainText: false) }
            HiddenShortcut(key: .return, modifiers: .shift) { pasteSelected(plainText: true) }
            HiddenShortcut(key: "c", modifiers: .command) { copySelected() }
            HiddenShortcut(key: .delete, modifiers: .command) {
                if appState.navigationMode == .clipboard { viewModel.deleteSelected() }
            }
            HiddenShortcut(key: "y", modifiers: .command) {
                if appState.navigationMode == .clipboard { viewModel.togglePreview() }
            }
            HiddenShortcut(key: "f", modifiers: .command) { searchFocused = true }
            HiddenShortcut(key: "n", modifiers: [.command, .shift]) { showingNewBoard = true }
            quickPasteShortcuts
        }
    }

    @ViewBuilder
    private var quickPasteShortcuts: some View {
        let keys = Array("123456789")
        ForEach(0..<min(9, clips.count), id: \.self) { index in
            HiddenShortcut(key: KeyEquivalent(keys[index]), modifiers: .command) {
                if appState.navigationMode == .clipboard {
                    viewModel.paste(clips[index])
                }
            }
        }
    }

    private func handleEscape() {
        if appState.previewClipID != nil {
            viewModel.closePreview()
        } else if !appState.searchText.isEmpty {
            appState.searchText = ""
        } else {
            viewModel.hideHistory()
        }
    }

    private func pasteSelected(plainText: Bool) {
        switch appState.navigationMode {
        case .clipboard:
            viewModel.pasteSelected(plainText: plainText)
        case .aiMemory, .favorites:
            aiViewModel.pasteSelected(plainText: plainText)
        }
    }

    private func copySelected() {
        switch appState.navigationMode {
        case .clipboard:
            viewModel.copySelected()
        case .aiMemory, .favorites:
            aiViewModel.copySelected()
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func clipContextMenu(_ clip: ClipItem) -> some View {
        Button("Paste") { viewModel.paste(clip) }
        Button("Paste as Plain Text") { viewModel.paste(clip, plainText: true) }
        Button("Copy") { viewModel.copyOnly(clip) }
        Button("Preview") { viewModel.togglePreview(clip) }
        if clip.url != nil {
            Button("Open Link") { viewModel.openLink(clip) }
        }
        if clip.contentType == .file {
            Button("Reveal in Finder") { viewModel.revealInFinder(clip) }
        }
        Divider()
        Button(viewModel.isFavorite(clip) ? "Remove from Favorites" : "Add to Favorites") {
            viewModel.toggleFavorite(clip)
        }
        if !viewModel.pinboards.isEmpty {
            Menu("Pin to") {
                ForEach(viewModel.pinboards) { board in
                    Button {
                        viewModel.togglePin(clip, on: board)
                    } label: {
                        if viewModel.isPinned(clip, to: board) {
                            Label(board.name, systemImage: "checkmark")
                        } else {
                            Text(board.name)
                        }
                    }
                }
            }
        } else {
            Button("New Pinboard…") { showingNewBoard = true }
        }
        Button("Add to Paste Stack") { viewModel.addToStack(clip) }
        Button("Rename…") {
            renameDraft = clip.title ?? ""
            clipBeingRenamed = clip
        }
        Divider()
        Button("Delete", role: .destructive) { viewModel.delete([clip]) }
    }
}
