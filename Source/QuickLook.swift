import AppKit
import Quartz

/// Pure AppKit bridge to the system Quick Look panel.
///
/// Owns the `QLPreviewPanel` data source / delegate plumbing only — no published state.
/// Selection state and "which files are in the grid" live on `ScreenshotStore`; the store
/// tells this bridge what to do (open/close/navigate), and the bridge feeds the panel's
/// item-count / item-at-index callbacks from the snapshot the store passes in.
///
/// `@MainActor`: `QLPreviewPanel` is an NSWindow subclass and may only be touched on main.
/// The bridge is owned by the `@MainActor` store and only called from it, so the compiler
/// guarantees all panel access is main-thread — no manual `Thread.isMainThread` checks needed.
@MainActor
final class QuickLookPanelBridge: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    /// Snapshot of the file list the panel is currently previewing. Updated by the store
    /// via `toggle`/`refreshItems` whenever the grid changes.
    ///
    /// `nonisolated(unsafe)`: read by the `nonisolated` QLPreviewPanelDataSource callbacks
    /// (`numberOfPreviewItems`, `previewItemAt:`). AppKit invokes those callbacks on the main
    /// thread, and the class is `@MainActor`, so all reads/writes are main-thread in practice.
    nonisolated(unsafe) private var items: [URL] = []

    /// Open the Quick Look panel at `url` if closed, or close it if open.
    /// `selection` is owned by the store; this method only drives the panel imperatively.
    func toggle(url: URL, in all: [URL]) {
        items = all
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.dataSource = self
            panel.delegate = self
            panel.currentPreviewItemIndex = max(0, all.firstIndex(of: url) ?? 0)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Update the panel's item list + current index after a file is renamed. No-op if the
    /// panel isn't open. (Main-thread safety is guaranteed by `@MainActor`.)
    func refreshItems(to all: [URL], current: URL?) {
        items = all
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        panel.dataSource = self
        if let current {
            panel.currentPreviewItemIndex = max(0, all.firstIndex(of: current) ?? 0)
        }
    }

    /// Dismiss the Quick Look panel if it's currently open. Used when the underlying files
    /// are deleted/swept, so the panel never shows stale items.
    func closeIfOpen() {
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        }
    }

    /// Advance the panel's current index (arrow-key navigation). No-op if the panel isn't open.
    func setPanelIndex(_ index: Int) {
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        panel.currentPreviewItemIndex = index
    }

    // MARK: QLPreviewPanelDataSource
    //
    // `nonisolated`: QLPreviewPanelDataSource is an ObjC protocol whose methods aren't
    // @MainActor-annotated, so a @MainActor conforming type would otherwise trigger a
    // "conformance crosses into main actor-isolated code" warning. AppKit invokes these
    // from main, and the class is @MainActor, so the runtime contract holds either way.

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard items.indices.contains(index) else { return nil }
        return items[index] as NSURL
    }
}
