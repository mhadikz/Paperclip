import SwiftUI
import AppKit

struct PinboardManagerView: View {
    @EnvironmentObject private var viewModel: ClipboardViewModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @ViewState private var newName = ""
    @ViewState private var newColorHex = Pinboard.defaultColorHex
    @ViewState private var renameDraft = ""
    @ViewState private var boardBeingRenamed: Pinboard?

    var body: some View {
        VStack(spacing: 0) {
            header
            if viewModel.pinboards.isEmpty {
                emptyState
            } else {
                boardList
            }
            newBoardRow
        }
        .appWindowFill()
        .alert("Rename Pinboard", isPresented: Binding(
            get: { boardBeingRenamed != nil },
            set: { if !$0 { boardBeingRenamed = nil } }
        )) {
            TextField("Name", text: $renameDraft)
            Button("Save") {
                if let board = boardBeingRenamed {
                    viewModel.renamePinboard(board, name: renameDraft)
                }
                boardBeingRenamed = nil
            }
            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {
                boardBeingRenamed = nil
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Pinboards")
                .font(AppTheme.headline)
            Spacer()
            Button("Done") { dismiss() }
                .appGlassButton()
        }
        .padding(.horizontal, AppTheme.spaceL)
        .padding(.vertical, AppTheme.spaceM)
    }

    private var emptyState: some View {
        AppEmptyState(
            systemImage: "tray",
            title: "No pinboards yet",
            subtitle: "Create one below to group clips you want to keep."
        )
    }

    private var boardList: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.spaceS) {
                ForEach(viewModel.pinboards) { board in
                    boardRow(board)
                }
            }
            .padding(AppTheme.spaceL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func boardRow(_ board: Pinboard) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceS) {
            HStack(spacing: AppTheme.spaceS) {
                Circle()
                    .fill(board.color)
                    .frame(width: 10, height: 10)
                Text(board.name)
                    .font(AppTheme.bodyMedium)
                    .lineLimit(1)
                Spacer()
                Text("\(board.clipIDs.count)")
                    .font(AppTheme.captionMono)
                    .foregroundStyle(.secondary)
                Button("Show") {
                    appState.selectedPinboardID = board.id
                    dismiss()
                }
                .appGlassButton()
                Button {
                    renameDraft = board.name
                    boardBeingRenamed = board
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: AppTheme.iconButton, height: AppTheme.iconButton)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .appIconGlass()
                .help("Rename")
                Button(role: .destructive) {
                    viewModel.confirmDeletePinboard(board)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: AppTheme.iconButton, height: AppTheme.iconButton)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .appIconGlass()
                .help("Delete")
            }
            HStack(spacing: AppTheme.spaceS) {
                ForEach(Pinboard.colorPalette, id: \.self) { hex in
                    Button {
                        viewModel.setPinboardColor(board, colorHex: hex)
                    } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? AppPalette.brand)
                            .frame(width: 16, height: 16)
                            .overlay {
                                if board.colorHex.lowercased() == hex.lowercased() {
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.8), lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Set color")
                }
            }
        }
        .padding(AppTheme.spaceM)
        .appContentSurface()
    }

    private var newBoardRow: some View {
        HStack(spacing: AppTheme.spaceS) {
            ForEach(Pinboard.colorPalette, id: \.self) { hex in
                Button {
                    newColorHex = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex) ?? AppPalette.brand)
                        .frame(width: 14, height: 14)
                        .overlay {
                            if newColorHex == hex {
                                Circle().strokeBorder(Color.primary.opacity(0.8), lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            TextField("New pinboard name", text: $newName)
                .textFieldStyle(.plain)
                .onSubmit(createBoard)
            Button("Add") { createBoard() }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .appGlassProminentButton()
        }
        .padding(AppTheme.spaceM)
        .appControlGlass()
        .padding(.horizontal, AppTheme.spaceL)
        .padding(.bottom, AppTheme.spaceM)
    }

    private func createBoard() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        viewModel.createPinboard(name: name, colorHex: newColorHex)
        newName = ""
    }
}
