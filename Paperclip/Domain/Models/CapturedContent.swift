import Foundation

/// What the pasteboard monitor observed. Carries raw data only — no AppKit image objects —
/// so capture can hand work to background actors without main-thread hops.
enum CapturedContent: Equatable {
    /// Plain text plus, when the source app provided it, the RTF representation (bounded in size).
    case text(String, richText: Data?)
    /// PNG-encoded image bytes.
    case image(Data)
    /// File URLs copied from Finder or another app.
    case files([URL])
}
