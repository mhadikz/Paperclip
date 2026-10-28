import Foundation
import AppKit
import Vision

/// Files that live next to history: image PNGs and RTF sidecars.
struct MediaStore: MediaStoring {
    let rootURL: URL

    init(rootURL: URL = AppDataLocation.mediaURL) {
        self.rootURL = rootURL
    }

    func url(for fileName: String) -> URL {
        rootURL.appendingPathComponent(fileName)
    }

    func saveImageData(_ data: Data, id: UUID) -> String? {
        let name = "\(id.uuidString).png"
        return saveData(data, fileName: name) ? name : nil
    }

    func saveData(_ data: Data, fileName: String) -> Bool {
        do {
            try data.write(to: url(for: fileName), options: .atomic)
            return true
        } catch {
            AppLogger.error("Media write failed: \(error.localizedDescription)", logger: AppLogger.persistence)
            return false
        }
    }

    func loadData(fileName: String) -> Data? {
        try? Data(contentsOf: url(for: fileName))
    }

    func loadImage(fileName: String) -> NSImage? {
        NSImage(contentsOf: url(for: fileName))
    }

    func delete(fileName: String?) {
        guard let fileName else { return }
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    func fileSize(fileName: String?) -> Int {
        guard let fileName else { return 0 }
        return (try? url(for: fileName).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    func totalByteCount() -> Int {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return items.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Vision OCR, run off the main thread. Returns nil when nothing legible is found.
    func recognizeText(inImageData data: Data) async -> String? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return nil
            }
            let observations = (request.results ?? [])
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }.value
    }
}
