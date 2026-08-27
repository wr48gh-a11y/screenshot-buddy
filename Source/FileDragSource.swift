import SwiftUI
import AppKit
import os

/// AppKit-owned drag source laid over a grid cell's thumbnail.
///
/// Why this exists: SwiftUI's own drag modifiers (`.onDrag`, then `.draggable`) both shipped
/// with the same symptom, pressing the newest (top-left) cell acted on the cell to its right.
/// Moving drag into AppKit gives us a real `NSView` frame we can log and hit-test, which is how
/// the actual cause was finally found: the neighbouring thumbnail's unclipped overflow, not the
/// drag API. See `ThumbnailView` for the fix and HANDOFF.md for the full story.
///
/// Keeping drag here is still the right call. AppKit hit-tests real `NSView` frames, the view
/// under the pointer receives `mouseDown`, and it starts a dragging session carrying its own
/// `url`. Nothing is cached between cells, so there is no stale state to recycle.
///
/// The view also handles single click (select) and double click (open) since it sits on top of
/// the thumbnail and would otherwise swallow them. Right-click is left alone: `NSView`'s default
/// `rightMouseDown` finds no menu here and forwards to the hosting view, so the SwiftUI
/// `.contextMenu` on the cell still appears.
struct FileDragSource: NSViewRepresentable {
    let url: URL
    let onClick: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> FileDragSourceView {
        let view = FileDragSourceView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: FileDragSourceView, context: Context) {
        apply(to: view)
    }

    /// Pin the view to the thumbnail's size. An `NSViewRepresentable` has no intrinsic size, so
    /// without this SwiftUI hands it the full proposed width: inside a `GridRow` that proposal is
    /// the whole row, and the drag view ends up wider than its cell, lying on top of the cell
    /// next to it and swallowing its clicks. Same failure mode as the thumbnail overflow that
    /// caused the "can't drag the newest screenshot" bug, from the other direction.
    /// Covered by `CellHitTestingTests.testDragViewIsPinnedToThumbnailSize`.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FileDragSourceView, context: Context) -> CGSize? {
        CGSize(width: ThumbnailView.width, height: ThumbnailView.height)
    }

    private func apply(to view: FileDragSourceView) {
        view.url = url
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        view.toolTip = url.lastPathComponent
    }
}

final class FileDragSourceView: NSView, NSDraggingSource {
    var url: URL?
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    /// Where the current press started, in window coordinates. Nil once a drag has begun or
    /// the mouse has been released.
    private var pressOrigin: NSPoint?
    private static let dragThreshold: CGFloat = 4

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ScreenshotBuddy",
                                    category: "drag")

    // The panel is a non-activating menu bar window; the first click must count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressOrigin = event.locationInWindow
        // Select on press, like Finder, so the highlight tracks the cell being dragged.
        onClick?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = pressOrigin, let url else { return }
        let location = event.locationInWindow
        guard hypot(location.x - origin.x, location.y - origin.y) >= Self.dragThreshold else { return }
        pressOrigin = nil

        Self.log.log("drag begin: \(url.lastPathComponent, privacy: .public)")
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: dragImage(for: url))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard pressOrigin != nil else { return }
        pressOrigin = nil
        if event.clickCount == 2 { onDoubleClick?() }
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Copy only: a file URL dropped on Finder must never move the original out of the
        // screenshots folder behind the user's back.
        context == .outsideApplication ? .copy : []
    }

    // MARK: Drag image

    /// Snapshot of the SwiftUI thumbnail this view sits on, so the drag preview matches what the
    /// user grabbed. Falls back to the file's icon if the hosting view can't be captured.
    private func dragImage(for url: URL) -> NSImage {
        if let host = superview,
           let rep = host.bitmapImageRepForCachingDisplay(in: frame) {
            host.cacheDisplay(in: frame, to: rep)
            let image = NSImage(size: frame.size)
            image.addRepresentation(rep)
            return image
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
