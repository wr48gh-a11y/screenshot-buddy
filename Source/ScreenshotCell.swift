import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Grid item

struct ScreenshotCell: View {
    @EnvironmentObject var store: ScreenshotStore
    let url: URL
    @State private var renaming = false
    @State private var newName = ""
    @State private var renameError: String?
    @State private var trashError = false
    @State private var hovering = false
    @FocusState private var nameFocused: Bool

    private var isSelected: Bool { store.selection == url }

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
                        .foregroundStyle(Theme.errorText)
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
                if trashError {
                    Text("Couldn't move to Trash — file may be in use.")
                        .font(.caption2)
                        .foregroundStyle(Theme.errorText)
                        .frame(width: ThumbnailView.width)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(hovering && !isSelected ? Color.white.opacity(0.08) : .clear)
        )
        .onHover { hovering = $0 }
        .onChange(of: store.selection) { _, _ in
            if trashError { withAnimation { trashError = false } }
        }
        .help(url.lastPathComponent)
        // .draggable, not .onDrag: onDrag's NSItemProvider was resolved through a stale
        // gesture-layer cache in the lazy grid, so dragging the newest cell handed out the
        // second-newest file. draggable's payload is an autoclosure evaluated at drag start,
        // so it always reads this cell's current url. The NSLog lets us confirm from the
        // unified log which file a drag actually carried if this ever regresses.
        .draggable(dragPayload)
        .gesture(TapGesture(count: 2).onEnded { NSWorkspace.shared.open(url) })
        .simultaneousGesture(TapGesture(count: 1).onEnded { store.select(url) })
        .contextMenu {
            Button("Quick Look") { store.toggleQuickLook(url) }
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Rename") { beginRename() }
            Divider()
            Button("Move to Trash", role: .destructive) {
                let ok = store.moveToTrash(url)
                if !ok { withAnimation { trashError = true } }
            }
        }
    }

    /// Evaluated lazily (via draggable's autoclosure) at the instant a drag begins.
    private var dragPayload: URL {
        NSLog("ScreenshotBuddy drag begin: %@", url.lastPathComponent)
        return url
    }

    private func beginRename() {
        newName = url.deletingPathExtension().lastPathComponent
        renameError = nil
        trashError = false
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
        case .inUse:
            renameError = "Couldn't rename — file may be in use"
        }
    }
}
