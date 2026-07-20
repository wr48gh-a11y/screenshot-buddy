import SwiftUI
import AppKit
import QuickLookThumbnailing

/// Loads a single thumbnail via the system Quick Look generator.
final class ThumbnailLoader: ObservableObject {
    @Published var image: NSImage?
    @Published private(set) var isLoading = false
    func load(url: URL, size: CGFloat) {
        isLoading = true
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: size, height: size),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            DispatchQueue.main.async {
                self?.image = rep?.nsImage
                self?.isLoading = false
            }
        }
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
