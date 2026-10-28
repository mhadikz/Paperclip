import SwiftUI

/// Shared layout, type, and control tokens. Every surface should use these
/// instead of one-off padding, radii, or fonts.
enum AppTheme {
    static let radiusWindow: CGFloat = 20
    static let radiusCard: CGFloat = 18
    static let radiusControl: CGFloat = 14
    static let radiusChip: CGFloat = 10
    static let radiusKeycap: CGFloat = 6

    static let spaceXXS: CGFloat = 4
    static let spaceXS: CGFloat = 6
    static let spaceS: CGFloat = 10
    static let spaceM: CGFloat = 14
    static let spaceL: CGFloat = 20
    static let spaceXL: CGFloat = 24

    static let chipPadH: CGFloat = 8
    static let chipPadV: CGFloat = 4
    static let keycapPadH: CGFloat = 6
    static let keycapPadV: CGFloat = 3
    static let buttonPadH: CGFloat = 12
    static let buttonPadV: CGFloat = 6

    static let iconButton: CGFloat = 28
    static let titlebarLeading: CGFloat = 78
    static let emptyMaxWidth: CGFloat = 320

    static let title: Font = .title3.weight(.semibold)
    static let display: Font = .title.weight(.semibold)
    static let headline: Font = .headline
    static let body: Font = .body
    static let bodyMedium: Font = .body.weight(.medium)
    static let callout: Font = .callout
    static let calloutMedium: Font = .callout.weight(.medium)
    static let caption: Font = .caption
    static let captionMedium: Font = .caption.weight(.medium)
    static let caption2: Font = .caption2
    static let caption2Medium: Font = .caption2.weight(.medium)
    static let caption2Semibold: Font = .caption2.weight(.semibold)
    static let captionMono: Font = .caption.monospaced()
    static let keycap: Font = .caption.weight(.medium).monospaced()
    static let symbolLarge: Font = .largeTitle
    static let symbolTitle: Font = .system(size: 56, weight: .medium)
}
