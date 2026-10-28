import Foundation

/// Turns observed pasteboard content into history. This path must stay fast: no model
/// calls, no image decoding, no network. Everything slow is handed off after the insert.
@MainActor
struct CaptureClipUseCase {
    let clipboard: ClipboardRepositoryProtocol
    let pinboards: PinboardRepositoryProtocol
    let aiMemory: AIMemoryRepositoryProtocol
    let mediaStore: MediaStoring
    let settings: SettingsProviding
    let enqueueAI: EnqueueAIProcessingUseCase

    /// Larger payloads are almost never meant as "clips" and would make every save slow.
    static let maxTextCharacters = 1_000_000
    static let maxRichTextBytes = 512 * 1024

    func execute(content: CapturedContent, bundleID: String?, appName: String?) {
        guard settings.recordHistory else { return }
        guard !settings.isIgnored(bundleID: bundleID) else { return }

        switch content {
        case .text(let text, let richText):
            handleText(text, richText: richText, bundleID: bundleID, appName: appName)
        case .image(let data):
            handleImage(data, bundleID: bundleID, appName: appName)
        case .files(let urls):
            handleFiles(urls, bundleID: bundleID, appName: appName)
        }
    }

    // MARK: - Text

    private func handleText(_ text: String, richText: Data?, bundleID: String?, appName: String?) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        guard text.count <= Self.maxTextCharacters else {
            AppLogger.event("Skipped oversized text clip", logger: AppLogger.clipboard)
            return
        }

        if SensitiveContentFilter.looksSensitive(text) {
            switch settings.sensitiveStoragePolicy {
            case .neverStore:
                if settings.skipSensitiveContent {
                    AppLogger.event("Skipped sensitive clip", logger: AppLogger.clipboard)
                    return
                }
            case .storeWithoutAI:
                break
            case .storeEncryptedPlaceholder:
                insert(
                    ClipItem(
                        contentType: .text,
                        text: SensitiveContentFilter.redactedPlaceholder(for: text),
                        title: "Redacted secret",
                        sourceBundleID: bundleID,
                        sourceAppName: appName
                    ),
                    richText: nil
                )
                return
            }
        }

        insert(
            ClipItem(
                contentType: ClipItem.inferType(from: text),
                text: text,
                sourceBundleID: bundleID,
                sourceAppName: appName
            ),
            richText: richText
        )
    }

    // MARK: - Images

    private func handleImage(_ data: Data, bundleID: String?, appName: String?) {
        guard !data.isEmpty else { return }
        let hash = ContentHasher.sha256(data)

        if let existing = clipboard.clips.first(where: { $0.contentType == .image && $0.contentHash == hash }) {
            bump(existing, bundleID: bundleID, appName: appName)
            return
        }

        let id = UUID()
        guard let fileName = mediaStore.saveImageData(data, id: id) else {
            AppLogger.error("Could not write image clip to the media store", logger: AppLogger.clipboard)
            return
        }
        let item = ClipItem(
            id: id,
            contentType: .image,
            sourceBundleID: bundleID,
            sourceAppName: appName,
            mediaFileName: fileName,
            contentHash: hash,
            mediaByteCount: data.count
        )
        insert(item, richText: nil)

        let store = mediaStore
        Task { [clipboard, enqueueAI] in
            guard let ocr = await store.recognizeText(inImageData: data) else { return }
            guard var updated = clipboard.clip(id: id) else { return }
            updated.searchableText = ocr
            clipboard.update(updated)
            enqueueAI.execute(clip: updated)
        }
    }

    // MARK: - Files

    private func handleFiles(_ urls: [URL], bundleID: String?, appName: String?) {
        let paths = urls.map(\.path).filter { !$0.isEmpty }
        guard !paths.isEmpty else { return }
        insert(
            ClipItem(
                contentType: .file,
                text: paths.joined(separator: "\n"),
                sourceBundleID: bundleID,
                sourceAppName: appName,
                filePaths: paths
            ),
            richText: nil
        )
    }

    // MARK: - Shared

    private func insert(_ item: ClipItem, richText: Data?) {
        let result = clipboard.insert(item)
        var stored = result.clip

        switch result {
        case .inserted:
            if let richText, settings.captureRichText, richText.count <= Self.maxRichTextBytes {
                let name = "\(stored.id.uuidString).rtf"
                if mediaStore.saveData(richText, fileName: name) {
                    stored.richTextFileName = name
                    clipboard.update(stored)
                }
            }
            enqueueAI.execute(clip: stored)
        case .bumped:
            // Same content copied again: keep identity, pins, favorites and metadata.
            if stored.richTextFileName == nil, let richText, settings.captureRichText,
               richText.count <= Self.maxRichTextBytes {
                let name = "\(stored.id.uuidString).rtf"
                if mediaStore.saveData(richText, fileName: name) {
                    stored.richTextFileName = name
                }
            }
            stored.createdAt = Date()
            if let bundle = item.sourceBundleID { stored.sourceBundleID = bundle }
            if let app = item.sourceAppName { stored.sourceAppName = app }
            clipboard.update(stored)
            if aiMemory.metadata(for: stored.id) == nil {
                enqueueAI.execute(clip: stored)
            }
        }

        let removed = clipboard.trim(
            limit: max(1, settings.rememberCount),
            keepForever: pinboards.allPinnedIDs().union(aiMemory.favoriteIDs())
        )
        if !removed.isEmpty {
            aiMemory.remove(ids: Set(removed.map(\.id)))
        }
    }

    private func bump(_ existing: ClipItem, bundleID: String?, appName: String?) {
        var updated = existing
        updated.createdAt = Date()
        if let bundleID { updated.sourceBundleID = bundleID }
        if let appName { updated.sourceAppName = appName }
        clipboard.update(updated)
        clipboard.bumpToTop(id: updated.id)
    }
}
