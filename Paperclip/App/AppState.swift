import Foundation
import Combine

/// Shared UI shell state across features (not domain data).
@MainActor
final class AppState: ObservableObject {
    @Published var searchText = ""
    @Published var filterType: ClipContentType?
    @Published var navigationMode: HistoryNavigationMode = .clipboard
    @Published var selectedPinboardID: UUID?
    @Published var selectedClipID: UUID?
    @Published var selectedMemoryID: UUID?
    /// Clip shown full-size in Clipboard mode (⌘Y / Preview).
    @Published var previewClipID: UUID?
    @Published var isHistoryPresented = false
    /// Incremented on every show so views can re-focus search even when the window is reused.
    @Published var historyPresentationCount = 0

    /// History is a disposable session: close always starts fresh search/selection next open.
    func resetHistorySession() {
        searchText = ""
        filterType = nil
        selectedClipID = nil
        selectedMemoryID = nil
        previewClipID = nil
    }
}
