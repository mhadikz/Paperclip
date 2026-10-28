import AppKit
import Combine
import Foundation

/// Decodes downscaled image previews off the main thread and caches them, so History cards
/// never load full-resolution PNGs during layout.
@MainActor
final class ThumbnailStore: ObservableObject {
    @Published private(set) var version = 0

    private let mediaStore: MediaStoring
    private let cache = NSCache<NSString, NSImage>()
    private var inFlight = Set<String>()

    init(mediaStore: MediaStoring) {
        self.mediaStore = mediaStore
        cache.countLimit = 300
    }

    /// Returns the cached thumbnail or starts decoding it (nil until ready).
    func image(for clip: ClipItem, maxPixelSize: Int = 480) -> NSImage? {
        guard clip.contentType == .image, let fileName = clip.mediaFileName else { return nil }
        let key = "\(fileName)#\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard inFlight.insert(key as String).inserted else { return nil }

        let store = mediaStore
        Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                guard let data = store.loadData(fileName: fileName),
                      let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
                ]
                guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }.value
            guard let self else { return }
            self.inFlight.remove(key as String)
            if let image {
                self.cache.setObject(image, forKey: key)
                self.version &+= 1
            }
        }
        return nil
    }

    func evict(clip: ClipItem) {
        guard let fileName = clip.mediaFileName else { return }
        for size in [480, 1200] {
            cache.removeObject(forKey: "\(fileName)#\(size)" as NSString)
        }
    }
}
