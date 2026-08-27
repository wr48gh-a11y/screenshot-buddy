import XCTest
import SwiftUI
import AppKit
@testable import ScreenshotBuddy

/// Guards the bug that kept coming back: pressing the newest (top-left) screenshot did nothing,
/// or acted on its neighbour.
///
/// The cause was never the grid container. Screenshots are far wider than the 172pt cell, and
/// `ThumbnailView` renders them with `.aspectRatio(contentMode: .fill)`. `clipShape` clips
/// drawing but NOT hit testing, so each cell's image stayed interactive at its full unclipped
/// width and spilled sideways over its neighbour. In a `GridRow` the right-hand cell is
/// hit-tested first, so its invisible overflow covered the newest screenshot on the left and
/// swallowed every press on it.
///
/// This test builds a real two-cell `GridRow` with a deliberately over-wide image and asserts
/// that a press in the middle of the left cell reaches the LEFT cell's drag view. It fails if
/// the clipping (`.clipped()` + `.contentShape`) is ever removed from `ThumbnailView`.
@MainActor
final class CellHitTestingTests: XCTestCase {

    /// A screenshot-shaped image, far wider than a cell, so aspect-fill overflows sideways.
    private func wideImage() -> NSImage {
        let size = NSSize(width: 1600, height: 400)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    /// Every `FileDragSourceView` in the hierarchy, in tree order.
    private func dragViews(in view: NSView) -> [FileDragSourceView] {
        var found: [FileDragSourceView] = []
        if let v = view as? FileDragSourceView { found.append(v) }
        for sub in view.subviews { found.append(contentsOf: dragViews(in: sub)) }
        return found
    }

    func testPressOnLeftCellIsNotStolenByTheNeighbouringThumbnail() throws {
        let store = ScreenshotStore(forTesting: ())
        let left = URL(fileURLWithPath: "/tmp/screenshot-buddy-left.png")
        let right = URL(fileURLWithPath: "/tmp/screenshot-buddy-right.png")
        let image = wideImage()

        let row = Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                ScreenshotCell(url: left, previewImage: image).id(left)
                ScreenshotCell(url: right, previewImage: image).id(right)
            }
        }
        .padding(12)
        .environmentObject(store)

        let host = NSHostingView(rootView: row)
        host.frame = NSRect(x: 0, y: 0, width: 424, height: 220)
        let window = NSWindow(contentRect: host.frame,
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        let views = dragViews(in: host)
        XCTAssertEqual(views.count, 2, "Expected one drag view per cell")
        let leftView = try XCTUnwrap(views.first { $0.url == left },
                                     "No drag view carrying the left cell's URL")

        // Press dead centre of the left cell, in window coordinates.
        let centre = leftView.convert(NSPoint(x: leftView.bounds.midX, y: leftView.bounds.midY),
                                      to: nil)
        let hit = window.contentView?.hitTest(centre)

        XCTAssertTrue(hit === leftView,
                      "Press at the centre of the left cell landed on \(String(describing: hit)) "
                      + "instead of the left cell's own drag view. The neighbouring thumbnail's "
                      + "unclipped overflow is stealing the press again — check that "
                      + "ThumbnailView still applies .clipped() and .contentShape().")
    }

    /// The drag view must stay the size of the thumbnail. An `NSViewRepresentable` has no
    /// intrinsic size, so without `sizeThatFits` SwiftUI hands it the whole row's width and it
    /// covers its neighbour, which is the same failure from the other direction.
    func testDragViewIsPinnedToThumbnailSize() throws {
        let store = ScreenshotStore(forTesting: ())
        let url = URL(fileURLWithPath: "/tmp/screenshot-buddy-single.png")

        let host = NSHostingView(rootView:
            ScreenshotCell(url: url, previewImage: wideImage()).environmentObject(store))
        host.frame = NSRect(x: 0, y: 0, width: 424, height: 200)
        let window = NSWindow(contentRect: host.frame,
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        let view = try XCTUnwrap(dragViews(in: host).first)
        XCTAssertEqual(view.bounds.width, ThumbnailView.width, accuracy: 0.5)
        XCTAssertEqual(view.bounds.height, ThumbnailView.height, accuracy: 0.5)
    }
}
