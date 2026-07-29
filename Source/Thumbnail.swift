import SwiftUI
import AppKit
import QuickLookThumbnailing

/// Loads a single thumbnail via the system Quick Look generator.
///
/// Holds the in-flight request so it can be cancelled when the cell scrolls off-screen,
/// preventing a backlog of thumbnail jobs (and outdated images flashing in) during fast
/// scrolling through a large folder.
final class ThumbnailLoader: ObservableObject {
    @Published var image: NSImage?
    @Published private(set) var isLoading = false
    private var request: QLThumbnailGenerator.Request?

    func load(url: URL, size: CGFloat) {
        cancel()
        isLoading = true
        let req = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: size, height: size),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        request = req
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            DispatchQueue.main.async {
                self?.image = rep?.nsImage
                self?.isLoading = false
                self?.request = nil
            }
        }
    }

    /// Cancel any in-flight generation. Safe to call when nothing is loading.
    func cancel() {
        if let request {
            QLThumbnailGenerator.shared.cancel(request)
            self.request = nil
        }
        isLoading = false
    }
}

struct ThumbnailView: View {
    let url: URL
    @StateObject private var loader = ThumbnailLoader()

    static let width: CGFloat = 172
    static let height: CGFloat = 108   // 16:10, like a screenshot

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.07))
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.width, height: Self.height)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                if loader.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: Self.width, height: Self.height)
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        .onAppear { loader.load(url: url, size: Self.width) }
        .onDisappear { loader.cancel() }
        .id(url)
    }
}

/// Shared formatter — RelativeDateTimeFormatter is expensive to construct, so build it once.
private let relativeDateFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

func relativeLabel(for url: URL) -> String {
    guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return "" }
    return relativeDateFormatter.localizedString(for: date, relativeTo: Date())
}
