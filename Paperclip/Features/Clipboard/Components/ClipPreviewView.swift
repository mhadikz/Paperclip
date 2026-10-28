import SwiftUI
import AppKit

/// Full-size view of one clip inside the History panel (⌘Y / Preview).
struct ClipPreviewView: View {
    @EnvironmentObject private var viewModel: ClipboardViewModel
    @EnvironmentObject private var thumbnails: ThumbnailStore

    let clip: ClipItem
    let onBack: () -> Void

    private var metadata: AIMemoryMetadata? { viewModel.metadata(for: clip) }
    private var kind: ClipCardKind { ClipCardKind.resolve(clip: clip, metadata: metadata) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spaceM) {
                    content
                    details
                    if let meta = metadata, meta.summary != nil || !meta.tags.isEmpty {
                        memory(meta)
                    }
                }
                .padding(.horizontal, AppTheme.spaceL)
                .padding(.bottom, AppTheme.spaceM)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: AppTheme.spaceS) {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
                    .font(AppTheme.calloutMedium)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("[", modifiers: .command)

            Spacer()

            Button {
                viewModel.toggleFavorite(clip)
            } label: {
                Image(systemName: viewModel.isFavorite(clip) ? "star.fill" : "star")
                    .frame(width: AppTheme.iconButton, height: AppTheme.iconButton)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .appIconGlass()
            .foregroundStyle(viewModel.isFavorite(clip) ? AppPalette.brand : Color.secondary)
            .help(viewModel.isFavorite(clip) ? "Remove from Favorites" : "Add to Favorites")

            Button("Copy") { viewModel.copyOnly(clip) }
                .appGlassButton()
            Button("Paste") { viewModel.paste(clip) }
                .appGlassProminentButton()
        }
        .padding(.horizontal, AppTheme.spaceL)
        .padding(.bottom, AppTheme.spaceM)
    }

    @ViewBuilder
    private var content: some View {
        switch clip.contentType {
        case .image:
            if let image = thumbnails.image(for: clip, maxPixelSize: 1200) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusChip, style: .continuous))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
            if let ocr = clip.searchableText, !ocr.isEmpty {
                section("Recognized text") {
                    Text(ocr)
                        .font(AppTheme.callout)
                        .textSelection(.enabled)
                }
            }
        case .file:
            section(clip.filePaths.count == 1 ? "File" : "\(clip.filePaths.count) files") {
                VStack(alignment: .leading, spacing: AppTheme.spaceXS) {
                    ForEach(clip.filePaths, id: \.self) { path in
                        HStack(spacing: AppTheme.spaceS) {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                            Text(path)
                                .font(AppTheme.captionMono)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                    Button("Reveal in Finder") { viewModel.revealInFinder(clip) }
                        .appGlassButton()
                        .padding(.top, AppTheme.spaceXS)
                }
            }
        case .link:
            section("Link") {
                VStack(alignment: .leading, spacing: AppTheme.spaceS) {
                    Text(clip.text ?? "")
                        .font(AppTheme.callout)
                        .foregroundStyle(AppPalette.link)
                        .textSelection(.enabled)
                    Button("Open in Browser") { viewModel.openLink(clip) }
                        .appGlassButton()
                }
            }
        case .text:
            section(kind == .code ? "Code" : "Text") {
                Text(clip.text ?? "")
                    .font(.system(.callout, design: kind == .code ? .monospaced : .default))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var details: some View {
        section("Details") {
            VStack(alignment: .leading, spacing: AppTheme.spaceXS) {
                detailRow("Copied", clip.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let app = clip.sourceAppName {
                    detailRow("From", app)
                }
                switch clip.contentType {
                case .text, .link:
                    detailRow("Size", "\(clip.characterCount.formatted()) characters · \(clip.lineCount.formatted()) line\(clip.lineCount == 1 ? "" : "s")")
                    if clip.richTextFileName != nil {
                        detailRow("Formatting", "Rich text preserved")
                    }
                case .image:
                    if let bytes = clip.mediaByteCount {
                        detailRow("Size", ByteCountText.string(bytes))
                    }
                case .file:
                    EmptyView()
                }
                let boards = viewModel.pinboards(containing: clip)
                if !boards.isEmpty {
                    detailRow("Pinboards", boards.map(\.name).joined(separator: ", "))
                }
            }
        }
    }

    private func memory(_ meta: AIMemoryMetadata) -> some View {
        section("Memory") {
            VStack(alignment: .leading, spacing: AppTheme.spaceS) {
                if let summary = meta.summary {
                    Text(summary)
                        .font(AppTheme.callout)
                }
                if !meta.tags.isEmpty {
                    HStack(spacing: AppTheme.spaceXS) {
                        ForEach(meta.tags, id: \.self) { AppChip(title: $0) }
                    }
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spaceS) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
        .font(AppTheme.caption)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceS) {
            Text(title)
                .font(AppTheme.captionMedium)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spaceM)
        .appContentSurface()
    }
}
