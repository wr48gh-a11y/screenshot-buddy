import AppKit
import Quartz

/// Bridges the menu-bar grid to the system Quick Look panel (Space-to-preview, arrow keys).
final class QuickLook: NSObject, ObservableObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLook()
    @Published var selection: URL?
    private var items: [URL] = []

    func toggle(_ url: URL, in all: [URL]) {
        items = all
        selection = url
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

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        items[index] as NSURL
    }
}
