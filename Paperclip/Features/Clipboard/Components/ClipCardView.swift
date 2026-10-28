import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ClipCardView: View {
    let clip: ClipItem
    var metadata: AIMemoryMetadata? = nil
    var pinboards: [Pinboard] = []
    var thumbnail: NSImage? = nil
    var isFavorite = false
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onPaste: (_ plainText: Bool) -> Void
    var onPinboardTap: ((Pinboard) -> Void)? = nil

    @ViewState private var isHovered = false

    private var kind: ClipCardKind {
        ClipCardKind.resolve(clip: clip, metadata: metadata)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceS) {
            header
            contentBox
            if !pinboards.isEmpty {
                pinboardRow
            }
        }
        .padding(AppTheme.spaceM)
        .appContentSurface(selected: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.radiusCard, style: .continuous))
        .onTapGesture(count: 2) {
            onPaste(false)
        }
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrag { dragProvider() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var header: some View {
        HStack(spacing: AppTheme.spaceS) {
            ClipTypeBadge(kind: kind)
            if let app = clip.sourceAppName, !app.isEmpty {
                Text(app)
                    .font(AppTheme.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Text(ShortRelativeTime.string(from: clip.createdAt))
                .font(AppTheme.caption)
                .foregroundStyle(.tertiary)
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(AppTheme.caption2)
                    .foregroundStyle(AppPalette.brand)
                    .accessibilityLabel("Favorite")
            }
            Spacer(minLength: AppTheme.spaceS)
            if isHovered || isSelected {
                HistoryShortcutHint(keys: ["⌘C"])
                    .transition(.opacity)
            }
            Button(action: onCopy) {
                Image(systemName: "square.on.square")
                    .font(AppTheme.bodyMedium)
                    .foregroundStyle(AppPalette.controlOn)
                    .frame(width: AppTheme.iconButton, height: AppTheme.iconButton)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .appIconGlass()
            .help("Copy to clipboard (⌘C)")
            .accessibilityLabel("Copy")
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var pinboardRow: some View {
        HStack(spacing: 6) {
            ForEach(pinboards.prefix(4)) { board in
                Button {
                    onPinboardTap?(board)
                } label: {
                    PinboardBadge(board: board)
                }
                .buttonStyle(.plain)
                .help("Show \(board.name)")
            }
            if pinboards.count > 4 {
                Text("+\(pinboards.count - 4)")
                    .font(AppTheme.captionMedium)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var contentBox: some View {
        innerContent
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(AppTheme.spaceS)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusChip, style: .continuous)
                    .fill(kind.contentBackground)
            )
    }

    @ViewBuilder
    private var innerContent: some View {
        switch clip.contentType {
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: 140)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusChip, style: .continuous))
            } else {
                HStack(spacing: AppTheme.spaceS) {
                    Image(systemName: "photo")
                    Text(clip.preview == "Image" ? "Image" : clip.preview)
                        .lineLimit(2)
                }
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }
        case .file:
            HStack(alignment: .top, spacing: AppTheme.spaceS) {
                Image(systemName: clip.filePaths.count > 1 ? "doc.on.doc.fill" : "doc.fill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.preview)
                        .font(AppTheme.calloutMedium)
                        .lineLimit(2)
                    if let first = clip.filePaths.first, clip.filePaths.count == 1 {
                        Text(URL(fileURLWithPath: first).deletingLastPathComponent().path)
                            .font(AppTheme.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        case .link:
            VStack(alignment: .leading, spacing: 2) {
                if let title = clip.title, !title.isEmpty {
                    Text(title)
                        .font(AppTheme.calloutMedium)
                        .lineLimit(1)
                }
                Text(clip.text ?? clip.preview)
                    .font(AppTheme.callout)
                    .foregroundStyle(kind.badgeForeground)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        case .text:
            VStack(alignment: .leading, spacing: 2) {
                if let title = clip.title, !title.isEmpty {
                    Text(title)
                        .font(AppTheme.calloutMedium)
                        .lineLimit(1)
                }
                Text(clip.cardExcerpt)
                    .font(.system(.callout, design: kind == .code ? .monospaced : .default))
                    .foregroundStyle(.primary)
                    .lineLimit(kind == .code ? 6 : 4)
            }
        }
    }

    private var accessibilityDescription: String {
        var parts = [kind.badgeTitle, clip.preview]
        if let app = clip.sourceAppName { parts.append("from \(app)") }
        parts.append(ShortRelativeTime.string(from: clip.createdAt))
        return parts.joined(separator: ", ")
    }

    private func dragProvider() -> NSItemProvider {
        switch clip.contentType {
        case .text, .link:
            let text = clip.text ?? ""
            if let url = clip.url {
                return NSItemProvider(object: url as NSURL)
            }
            return NSItemProvider(object: text as NSString)
        case .file:
            if let first = clip.filePaths.first {
                return NSItemProvider(object: URL(fileURLWithPath: first) as NSURL)
            }
            return NSItemProvider()
        case .image:
            if let thumbnail {
                return NSItemProvider(object: thumbnail)
            }
            return NSItemProvider()
        }
    }
}
