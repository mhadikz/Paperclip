import Foundation
import AppKit
import Combine

// MARK: - Settings

@MainActor
final class StubSettings: SettingsProviding {
    var rememberCount = 1000
    var displayCount = 20
    var recordHistory = true
    var pasteAndEnter = true
    var captureRichText = true
    var confirmBeforeDeleting = false
    var skipSensitiveContent = true
    var sensitiveStoragePolicy: SensitiveStoragePolicy = .neverStore
    var aiFeaturesEnabled = true
    var automaticAIProcessing = true
    var automaticSummaries = true
    var automaticTags = true
    var semanticSearch = true
    var processSensitiveContent = false
    var useFoundationModels = true
    var hotKey: HotKeySpec = .default
    var ignored: Set<String> = []

    var snapshot: AppSettingsSnapshot {
        AppSettingsSnapshot(
            aiFeaturesEnabled: aiFeaturesEnabled,
            automaticAIProcessing: automaticAIProcessing,
            automaticSummaries: automaticSummaries,
            automaticTags: automaticTags,
            semanticSearch: semanticSearch,
            processSensitiveContent: processSensitiveContent,
            useFoundationModels: useFoundationModels,
            sensitiveStoragePolicy: sensitiveStoragePolicy
        )
    }

    func isIgnored(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return ignored.contains(bundleID)
    }
}

// MARK: - Media

/// Real file storage in a temp folder; OCR is stubbed so Vision never runs in tests.
struct StubMediaStore: MediaStoring {
    let inner: MediaStore
    let ocrResult: String?

    init(rootURL: URL, ocrResult: String? = nil) {
        inner = MediaStore(rootURL: rootURL)
        self.ocrResult = ocrResult
    }

    func saveImageData(_ data: Data, id: UUID) -> String? { inner.saveImageData(data, id: id) }
    func saveData(_ data: Data, fileName: String) -> Bool { inner.saveData(data, fileName: fileName) }
    func loadData(fileName: String) -> Data? { inner.loadData(fileName: fileName) }
    func loadImage(fileName: String) -> NSImage? { inner.loadImage(fileName: fileName) }
    func delete(fileName: String?) { inner.delete(fileName: fileName) }
    func fileSize(fileName: String?) -> Int { inner.fileSize(fileName: fileName) }
    func totalByteCount() -> Int { inner.totalByteCount() }
    func recognizeText(inImageData data: Data) async -> String? { ocrResult }
    func exists(_ fileName: String?) -> Bool {
        guard let fileName else { return false }
        return FileManager.default.fileExists(atPath: inner.url(for: fileName).path)
    }
}

// MARK: - Pasteboard

final class FakeMonitor: ClipboardMonitoring {
    var onNewContent: ((CapturedContent, String?, String?) -> Void)?
    var ignoreCount = 0
    func start() {}
    func stop() {}
    func ignoreCurrentChange() { ignoreCount += 1 }
}

@MainActor
final class FakePasteService: PasteServing {
    struct Write: Equatable {
        let clipID: UUID?
        let plainText: Bool
        let hasRichText: Bool
        let text: String?
    }
    var writes: [Write] = []
    var keystrokes: [TimeInterval] = []
    var canSendKeystrokes = true
    var accessibilityRequests = 0

    func write(_ item: ClipItem, plainText: Bool, richText: Data?) {
        writes.append(Write(clipID: item.id, plainText: plainText, hasRichText: richText != nil, text: item.text))
    }
    func writeText(_ text: String) {
        writes.append(Write(clipID: nil, plainText: true, hasRichText: false, text: text))
    }
    func sendPasteKeystroke(after delay: TimeInterval) {
        guard canSendKeystrokes else { return }
        keystrokes.append(delay)
    }
    func requestAccessibility() -> Bool {
        accessibilityRequests += 1
        return canSendKeystrokes
    }
}

// MARK: - AI

final class FakeAI: AIMemoryServicing, @unchecked Sendable {
    var classifyCalls = 0
    var summarizeCalls = 0
    var classification: AIClassificationResult?
    var providerID = "fake"
    var rewriteResult = "rewritten"

    func classify(clip: ClipItem, useAI: Bool) async -> AIClassificationResult {
        classifyCalls += 1
        return classification ?? HeuristicClassifier.classify(clip: clip)
    }
    func summarize(clip: ClipItem, useAI: Bool) async -> String? {
        summarizeCalls += 1
        return "summary"
    }
    func rewrite(text: String, style: SmartRewriteStyle, useAI: Bool) async throws -> String { rewriteResult }
    func interpretQuery(_ query: String, useAI: Bool) async -> AIQueryInterpretation { QueryInterpreter.heuristic(query) }
    func availabilityMessage() async -> String { "fake" }
    func isFoundationModelsAvailable() async -> Bool { false }
    func activeProviderID(useAI: Bool) async -> String { providerID }
}

actor FakeQueue: AIProcessingQueuing {
    private(set) var enqueued: [UUID] = []
    func enqueue(_ clipID: UUID) { enqueued.append(clipID) }
    func enqueueMany(_ clipIDs: [UUID]) { enqueued.append(contentsOf: clipIDs) }
    func pendingCount() -> Int { enqueued.count }
}

@MainActor
struct FakeConfirmation: ConfirmationPrompting {
    var answer = true
    func confirm(title: String, message: String, confirmTitle: String) -> Bool { answer }
}

// MARK: - World

/// A complete, isolated object graph backed by a temp directory.
@MainActor
final class TestWorld {
    let root: URL
    let settings = StubSettings()
    let media: StubMediaStore
    let clipboard: ClipboardRepository
    let pinboards: PinboardRepository
    let aiMemory: AIMemoryRepository
    let stack = PasteStackStore()
    let monitor = FakeMonitor()
    let paste = FakePasteService()
    let ai = FakeAI()
    let queue = FakeQueue()

    init(ocr: String? = nil) {
        root = TestTemp.directory("world")
        media = StubMediaStore(rootURL: root.appendingPathComponent("Media", isDirectory: true), ocrResult: ocr)
        try? FileManager.default.createDirectory(at: media.inner.rootURL, withIntermediateDirectories: true)
        clipboard = ClipboardRepository(persistence: ClipPersistence(rootURL: root), mediaStore: media, publishSnapshot: { _, _ in })
        pinboards = PinboardRepository(persistence: ClipPersistence(rootURL: root))
        aiMemory = AIMemoryRepository(store: AIMetadataStore(url: root.appendingPathComponent("ai-metadata.json")))
    }

    var enqueueAI: EnqueueAIProcessingUseCase {
        EnqueueAIProcessingUseCase(aiMemory: aiMemory, settings: settings, queue: queue)
    }

    var capture: CaptureClipUseCase {
        CaptureClipUseCase(clipboard: clipboard, pinboards: pinboards, aiMemory: aiMemory, mediaStore: media, settings: settings, enqueueAI: enqueueAI)
    }

    var pasteClip: PasteClipUseCase {
        PasteClipUseCase(clipboard: clipboard, mediaStore: media, pasteService: paste, settings: settings, monitor: monitor)
    }

    var deleteClips: DeleteClipsUseCase {
        DeleteClipsUseCase(clipboard: clipboard, pinboards: pinboards, aiMemory: aiMemory, stack: stack)
    }

    var processAI: ProcessAIMemoryUseCase {
        ProcessAIMemoryUseCase(clipboard: clipboard, aiMemory: aiMemory, settings: settings, ai: ai)
    }

    var searchMemory: SearchMemoryUseCase {
        SearchMemoryUseCase(settings: settings, ai: ai)
    }

    func copyText(_ text: String, app: String = "com.test.app", rtf: Data? = nil) {
        capture.execute(content: .text(text, richText: rtf), bundleID: app, appName: "Test")
    }

    /// Lets detached tasks (enqueue, OCR) settle.
    func settle() async {
        for _ in 0..<5 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 30_000_000)
    }
}

enum TestImages {
    /// A tiny valid PNG (2×2 pixels) whose pixels depend on `red`, so hashes differ when needed.
    static func png(red: UInt8 = 200) -> Data {
        let width = 2, height = 2
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = red; pixels[i + 1] = 120; pixels[i + 2] = 60; pixels[i + 3] = 255
        }
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return out as Data
    }
}
