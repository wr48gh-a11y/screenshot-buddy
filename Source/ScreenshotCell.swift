import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Grid item

struct ScreenshotCell: View {
    @EnvironmentObject var store: ScreenshotStore
    let url: URL
    @ObservedObject private var quickLook = QuickLook.shared
    @State private var renaming = false
    @State private var newName = ""
    @State private var renameError: String?
    @State private var hovering = false
    @FocusState private var nameFocused: Bool

    private var isSelected: Bool { quickLook.selection == url }

    var body: some View {
        VStack(spacing: 5) {
            ThumbnailView(url: url)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                )
            if renaming {
                TextField("Name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(width: ThumbnailView.width)
                    .focused($nameFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { renaming = false; renameError = nil }
                    .onChange(of: nameFocused) { _, focused in
                        guard !focused, renaming else { return }
                        // On blur: commit if the name is good; if there's an active error,
                        // cancel (close the field) instead of retrying the same bad name.
                        if renameError == nil { commitRename() } else { renaming = false; renameError = nil }
                    }
                    .onChange(of: newName) { _, _ in renameError = nil }
                if let renameError {
                    Text(renameError)
                        .font(.caption2)
                        .foregroundStyle(Color(red: 1.0, green: 0.61, blue: 0.58))
                        .frame(width: ThumbnailView.width)
                        .transition(.opacity)
                }
            } else {
                Text(relativeLabel(for: url))
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : Theme.textDim)
                    .frame(width: ThumbnailView.width)
                    .onTapGesture { beginRename() }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(hovering && !isSelected ? Color.white.opacity(0.08) : .clear)
        )
        .onHover { hovering = $0 }
        .help(url.lastPathComponent)
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .gesture(TapGesture(count: 2).onEnded { NSWorkspace.shared.open(url) })
        .simultaneousGesture(TapGesture(count: 1).onEnded { quickLook.selection = url })
        .contextMenu {
            Button("Quick Look") { quickLook.toggle(url, in: store.files) }
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Rename") { beginRename() }
            Divider()
            Button("Move to Trash", role: .destructive) { store.moveToTrash(url) }
        }
    }

    private func beginRename() {
        newName = url.deletingPathExtension().lastPathComponent
        renameError = nil
        renaming = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { nameFocused = true }
    }

    private func commitRename() {
        switch store.rename(url, to: newName) {
        case .success:
            renaming = false
            renameError = nil
        case .emptyName:
            renameError = "Name can't be empty"
        case .collision:
            renameError = "A file with that name already exists"
        case .invalidCharacters:
            renameError = "Name can't contain / or :"
        }
    }
}
