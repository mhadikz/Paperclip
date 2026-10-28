import Foundation
import AppKit

// MARK: - Pasteboard

protocol ClipboardMonitoring: AnyObject {
    var onNewContent: ((CapturedContent, String?, String?) -> Void)? { get set }
    func start()
    func stop()
    /// Marks the pasteboard's current change as ours so the next poll does not re-capture it.
    func ignoreCurrentChange()
}

@MainActor
protocol PasteServing {
    /// Writes the clip to the general pasteboard. `richText` is the RTF sidecar (if any).
    func write(_ item: ClipItem, plainText: Bool, richText: Data?)
    func writeText(_ text: String)
    /// Posts ⌘V to the frontmost app after `delay`. No-op when Accessibility is not granted.
    func sendPasteKeystroke(after delay: TimeInterval)
    var canSendKeystrokes: Bool { get }
    /// Shows the system Accessibility prompt once; returns the current trust state.
    @discardableResult
    func requestAccessibility() -> Bool
}

// MARK: - Media

protocol MediaStoring: Sendable {
    func saveImageData(_ data: Data, id: UUID) -> String?
    func saveData(_ data: Data, fileName: String) -> Bool
    func loadData(fileName: String) -> Data?
    func loadImage(fileName: String) -> NSImage?
    func delete(fileName: String?)
    func fileSize(fileName: String?) -> Int
    func totalByteCount() -> Int
    func recognizeText(inImageData data: Data) async -> String?
}

// MARK: - Settings

@MainActor
protocol SettingsProviding: AnyObject {
    var snapshot: AppSettingsSnapshot { get }
    var rememberCount: Int { get }
    var displayCount: Int { get }
    var recordHistory: Bool { get set }
    var pasteAndEnter: Bool { get }
    var captureRichText: Bool { get }
    var confirmBeforeDeleting: Bool { get }
    var skipSensitiveContent: Bool { get }
    var sensitiveStoragePolicy: SensitiveStoragePolicy { get }
    var aiFeaturesEnabled: Bool { get }
    var automaticAIProcessing: Bool { get }
    var automaticSummaries: Bool { get }
    var automaticTags: Bool { get }
    var semanticSearch: Bool { get }
    var processSensitiveContent: Bool { get }
    var useFoundationModels: Bool { get }
    var hotKey: HotKeySpec { get }

    func isIgnored(bundleID: String?) -> Bool
}

// MARK: - AI

/// High-level AI operations the app needs. Implemented by `AIService` (Data) over
/// language-model providers; tests use a stub.
protocol AIMemoryServicing: Sendable {
    func classify(clip: ClipItem, useAI: Bool) async -> AIClassificationResult
    func summarize(clip: ClipItem, useAI: Bool) async -> String?
    func rewrite(text: String, style: SmartRewriteStyle, useAI: Bool) async throws -> String
    func interpretQuery(_ query: String, useAI: Bool) async -> AIQueryInterpretation
    func availabilityMessage() async -> String
    func isFoundationModelsAvailable() async -> Bool
    func activeProviderID(useAI: Bool) async -> String
}

/// Serial background enrichment queue.
protocol AIProcessingQueuing: Sendable {
    func enqueue(_ clipID: UUID) async
    func enqueueMany(_ clipIDs: [UUID]) async
    func pendingCount() async -> Int
}

// MARK: - System integration

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

// MARK: - Confirmation

/// Blocking yes/no confirmation. Implemented with `NSAlert` in Data; tests auto-answer.
@MainActor
protocol ConfirmationPrompting {
    func confirm(title: String, message: String, confirmTitle: String) -> Bool
}
