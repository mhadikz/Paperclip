import SwiftUI
import AppKit

struct MemoryDetailView: View {
    @EnvironmentObject private var viewModel: AIMemoryViewModel
    @EnvironmentObject private var thumbnails: ThumbnailStore
    @EnvironmentObject private var settings: AppSettings

    let clip: ClipItem

    @ViewState private var tagDraft = ""

    private var metadata: AIMemoryMetadata? {
        viewModel.metadata(for: clip)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spaceM) {
                header
                originalContent
                metadataSection
                actionsSection
                if let actionOutput = viewModel.actionOutput {
                    outputSection(actionOutput)
                }
                relatedSection
            }
            .padding(.horizontal, AppTheme.spaceL)
            .padding(.bottom, AppTheme.spaceM)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceXS) {
            Text(clip.title ?? metadata?.summary ?? clip.preview)
                .font(AppTheme.title)
                .lineLimit(3)
            HStack(spacing: AppTheme.spaceS) {
                Label(
                    metadata?.category?.title ?? clip.contentType.title,
                    systemImage: metadata?.category?.systemImage ?? clip.contentType.systemImage
                )
                if let app = clip.sourceAppName {
                    Text("· \(app)")
                }
                Text("· \(clip.createdAt.formatted(date: .abbreviated, time: .shortened))")
            }
            .font(AppTheme.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spaceM)
        .appContentSurface()
    }

    private var originalContent: some View {
        glassSection("Original") {
            switch clip.contentType {
            case .image:
                if let image = thumbnails.image(for: clip, maxPixelSize: 1200) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusChip, style: .continuous))
                }
                if let ocr = clip.searchableText, !ocr.isEmpty {
                    Text(ocr)
                        .textSelection(.enabled)
                        .font(AppTheme.callout)
                }
            case .file:
                ForEach(clip.filePaths, id: \.self) { path in
                    Text(path)
                        .font(AppTheme.captionMono)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            default:
                Text(clip.text ?? "")
                    .textSelection(.enabled)
                    .font(.system(.callout, design: clipLooksLikeCode ? .monospaced : .default))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var metadataSection: some View {
        glassSection("Memory") {
            VStack(alignment: .leading, spacing: AppTheme.spaceS) {
                if let summary = metadata?.summary {
                    Text(summary)
                        .font(AppTheme.callout)
                        .textSelection(.enabled)
                }
                if let tags = metadata?.tags, !tags.isEmpty {
                    FlowRow(spacing: AppTheme.spaceXS) {
                        ForEach(tags, id: \.self) { tag in
                            AppChip(title: tag)
                                .contextMenu {
                                    Button("Remove Tag", role: .destructive) {
                                        var next = tags
                                        next.removeAll { $0 == tag }
                                        viewModel.updateTags(clip, tags: next)
                                    }
                                }
                        }
                    }
                }
                HStack(spacing: AppTheme.spaceS) {
                    TextField("Add tag", text: $tagDraft)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, AppTheme.spaceS)
                        .padding(.vertical, AppTheme.spaceXS)
                        .appControlGlass()
                        .onSubmit(addTag)
                    Button("Add", action: addTag)
                        .disabled(tagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .appGlassButton()
                }
                if let meta = metadata {
                    HStack(spacing: AppTheme.spaceS) {
                        Text(statusText(meta.status))
                        if let model = meta.modelIdentifier {
                            Text("· \(model == "apple.foundationModels" ? "Apple Intelligence" : "Heuristics")")
                        }
                    }
                    .font(AppTheme.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusText(_ status: AIProcessingStatus) -> String {
        switch status {
        case .pending: return "Waiting for enrichment"
        case .processing: return "Enriching…"
        case .completed: return "Enriched"
        case .skipped: return "Not sent to the model"
        case .failed: return "Enrichment failed"
        case .unavailable: return "Model unavailable"
        }
    }

    private func addTag() {
        let draft = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return }
        var tags = metadata?.tags ?? []
        tags.append(draft)
        viewModel.updateTags(clip, tags: tags)
        tagDraft = ""
    }

    private var actionsSection: some View {
        glassSection("Actions") {
            VStack(alignment: .leading, spacing: AppTheme.spaceS) {
                FlowRow(spacing: AppTheme.spaceS) {
                    Button("Paste") { viewModel.paste(clip) }
                        .appGlassProminentButton()
                    Button("Paste Plain") { viewModel.paste(clip, plainText: true) }
                        .appGlassButton()
                    Button(metadata?.isFavorite == true ? "Unfavorite" : "Favorite") {
                        viewModel.toggleFavorite(clip)
                    }
                    .appGlassButton()
                    Button("Copy") { viewModel.copyOnly(clip) }
                        .appGlassButton()
                }

                let actions = SmartActionCatalog.actions(for: clip, metadata: metadata)
                if settings.aiFeaturesEnabled, !actions.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.spaceXS) {
                        Text("Smart Actions")
                            .font(AppTheme.caption)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: AppTheme.spaceS)], alignment: .leading, spacing: AppTheme.spaceS) {
                            ForEach(actions) { action in
                                Button {
                                    viewModel.runSmartAction(action, on: clip)
                                } label: {
                                    HStack(spacing: AppTheme.spaceXS) {
                                        if viewModel.runningAction == action {
                                            ProgressView().controlSize(.mini)
                                        } else {
                                            Image(systemName: action.systemImage)
                                        }
                                        Text(action.title)
                                            .lineLimit(1)
                                    }
                                }
                                .disabled(viewModel.runningAction != nil)
                                .appGlassButton()
                            }
                        }
                    }
                }

                if let actionError = viewModel.actionError {
                    Label(actionError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AppPalette.danger)
                        .font(AppTheme.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func outputSection(_ text: String) -> some View {
        glassSection("AI Output") {
            VStack(alignment: .leading, spacing: AppTheme.spaceS) {
                Text(text)
                    .textSelection(.enabled)
                    .font(AppTheme.body)
                HStack {
                    Button("Paste Result") { viewModel.pasteTransformed(text) }
                        .appGlassProminentButton()
                    Button("Copy Result") { viewModel.copyText(text) }
                        .appGlassButton()
                    Button("Dismiss") { viewModel.clearActionOutput() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var relatedSection: some View {
        let related = viewModel.related(for: clip)
        return Group {
            if !related.isEmpty {
                glassSection("Related Memories") {
                    VStack(alignment: .leading, spacing: AppTheme.spaceS) {
                        ForEach(related) { item in
                            Button {
                                viewModel.selectMemory(item.id)
                            } label: {
                                HStack {
                                    Image(systemName: viewModel.metadata(for: item)?.category?.systemImage ?? item.contentType.systemImage)
                                        .foregroundStyle(AppPalette.brand)
                                    Text(viewModel.metadata(for: item)?.summary ?? item.preview)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(ShortRelativeTime.string(from: item.createdAt))
                                        .font(AppTheme.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func glassSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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

    private var clipLooksLikeCode: Bool {
        metadata?.category?.isCodeLike == true
    }
}

/// Wrapping horizontal layout for chips and small buttons.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
