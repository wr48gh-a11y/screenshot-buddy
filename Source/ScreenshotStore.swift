import AppKit
import UniformTypeIdentifiers

/// Owns the chosen folder, its file list, and all file mutations (sweep, delete, rename).
/// The single source of truth for panel state; views observe it via `@EnvironmentObject`.
final class ScreenshotStore: ObservableObject {
    static let shared = ScreenshotStore()

    @Published var folderURL: URL? {
        didSet { refresh() }
    }
    @Published var files: [URL] = []
    @Published var totalBytes: Int64 = 0
    /// True when the chosen folder can't be read (deleted, renamed, drive unplugged, stale bookmark).
    @Published var accessLost = false

    var reclaimable: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    private var monitor: DispatchSourceFileSystemObject?
    /// The folder we currently hold a security-scoped access claim on.
    private var accessedURL: URL?
    private static let bookmarkKey = "folderBookmark"

    static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif", "bmp", "webp"]

    /// Outcome of a bulk sweep: how many files moved, how many couldn't (in use, locked, etc.).
    struct SweepOutcome: Equatable {
        let moved: Int
        let failed: Int
        var total: Int { moved + failed }
    }

    init() {
        restoreBookmarkedFolder()
        refresh()
        startMonitoring()
    }

    // MARK: Security-scoped folder access (App Sandbox)

    /// Release the current security-scoped access claim, if any. Safe to call repeatedly.
    private func releaseAccess() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }

    /// Restore access to the previously chosen folder from a saved security-scoped bookmark.
    private func restoreBookmarkedFolder() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [.withSecurityScope],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &isStale) else { return }
        releaseAccess()   // never hold two claims at once
        _ = url.startAccessingSecurityScopedResource()
        accessedURL = url
        folderURL = url
        if isStale { saveBookmark(for: url) }   // refresh a stale bookmark in place
    }

    private func saveBookmark(for url: URL) {
        if let data = try? url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        }
    }

    /// Adopt a newly chosen folder: claim security-scoped access and persist a bookmark.
    private func adopt(_ url: URL) {
        releaseAccess()
        _ = url.startAccessingSecurityScopedResource()
        accessedURL = url
        saveBookmark(for: url)
        folderURL = url
    }

    /// Coalesces bursts of filesystem-watcher events into a single background refresh,
    /// so a sync client touching many files doesn't thrash the main thread.
    private var pendingRefresh: DispatchWorkItem?
    private static let refreshDebounceSeconds = 0.25

    /// Immediate refresh — use after explicit user actions (folder chosen, sweep, rename, …).
    func refresh() { performRefresh() }

    /// Debounced refresh — use from the filesystem watcher so rapid events coalesce.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performRefresh() }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refreshDebounceSeconds, execute: work)
    }

    /// Enumerate + sort + size off the main thread; only the published state update hops back.
    private func performRefresh() {
        pendingRefresh?.cancel(); pendingRefresh = nil
        guard let folder = folderURL else {
            applyState(files: [], totalBytes: 0, accessLost: false)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items: [URL]
            do {
                items = try FileManager.default.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles])
            } catch {
                // Folder is unreachable — don't pretend it's empty.
                self?.applyState(files: [], totalBytes: 0, accessLost: true)
                return
            }
            let filtered = items
                .filter { Self.imageTypes.contains($0.pathExtension.lowercased()) }
                .sorted { a, b in
                    let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return da > db
                }
            let bytes = filtered.reduce(Int64(0)) { sum, url in
                sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            self?.applyState(files: filtered, totalBytes: bytes, accessLost: false)
        }
    }

    /// Single main-thread entry point for mutating published state.
    private func applyState(files: [URL], totalBytes: Int64, accessLost: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.files = files
            self.totalBytes = totalBytes
            self.accessLost = accessLost
            self.startMonitoring()
        }
    }

    private func startMonitoring() {
        monitor?.cancel()
        monitor = nil
        guard let folder = folderURL else { return }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleRefresh() }
        source.setCancelHandler { close(fd) }
        source.resume()
        monitor = source
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select the folder where your screenshots are saved."
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            adopt(url)
        }
    }

    func reset() {
        releaseAccess()
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        folderURL = nil
        files = []
    }

    /// Moves every screenshot to the macOS Trash (recoverable the normal way).
    /// Returns how many moved and how many couldn't (so the UI can surface partial failures).
    @discardableResult
    func sweepAllToTrash() -> SweepOutcome {
        var moved = 0, failed = 0
        for url in files {
            if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
                moved += 1
            } else {
                failed += 1
            }
        }
        refresh()
        return SweepOutcome(moved: moved, failed: failed)
    }

    /// A sweep that has been moved aside but not yet permanently purged (the Undo window).
    private struct PendingSweep {
        let dir: URL
        let items: [(temp: URL, original: URL)]
    }
    private var pendingSweep: PendingSweep?
    /// Deterministic, UI-independent timer that makes a permanent sweep final after the Undo window,
    /// so pending files never linger even if the panel closes.
    private var autoPurgeWork: DispatchWorkItem?
    static let undoWindowSeconds = 5.0

    /// Sweeps every screenshot: moves them to a temporary holding area (so the action stays
    /// instant and recoverable during the Undo window) and returns how many moved vs. couldn't.
    /// After the window it is purged automatically; call `undoSweep()` to restore.
    /// Any prior sweep is finalized first.
    @discardableResult
    func deleteAll() -> SweepOutcome {
        purgeSweep()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sweep-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var moved: [(URL, URL)] = []
        var failed = 0
        for url in files {
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            if (try? FileManager.default.moveItem(at: url, to: dest)) != nil {
                moved.append((dest, url))
            } else {
                failed += 1
            }
        }
        pendingSweep = PendingSweep(dir: dir, items: moved)

        // Purge on a store-owned timer so it happens whether or not the panel is still open.
        let work = DispatchWorkItem { [weak self] in self?.purgeSweep() }
        autoPurgeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.undoWindowSeconds, execute: work)

        refresh()
        return SweepOutcome(moved: moved.count, failed: failed)
    }

    /// Restore the last swept screenshots to their original locations.
    func undoSweep() {
        autoPurgeWork?.cancel(); autoPurgeWork = nil
        guard let sweep = pendingSweep else { return }
        for (temp, original) in sweep.items {
            try? FileManager.default.moveItem(at: temp, to: original)
        }
        try? FileManager.default.removeItem(at: sweep.dir)
        pendingSweep = nil
        refresh()
    }

    /// Permanently discard the last swept screenshots (bypasses the Trash).
    func purgeSweep() {
        autoPurgeWork?.cancel(); autoPurgeWork = nil
        guard let sweep = pendingSweep else { return }
        try? FileManager.default.removeItem(at: sweep.dir)
        pendingSweep = nil
    }

    /// Move a single file to the macOS Trash (recoverable), keeping per-file delete consistent
    /// with the safe bulk sweep.
    func moveToTrash(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        refresh()
    }

    /// Why a rename might not have applied.
    enum RenameResult: Equatable {
        case success
        case emptyName
        case collision          // a file with that name already exists
        case invalidCharacters  // name contains / or :
    }

    func rename(_ url: URL, to newName: String) -> RenameResult {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return .emptyName }
        // macOS forbids "/" in filenames; ":" is the legacy HFS separator and shows as "/" in Finder.
        if name.contains("/") || name.contains(":") { return .invalidCharacters }
        let finalName = name.lowercased().hasSuffix("." + url.pathExtension.lowercased())
            ? name
            : name + "." + url.pathExtension
        let dest = url.deletingLastPathComponent().appendingPathComponent(finalName)
        if dest != url, FileManager.default.fileExists(atPath: dest.path) { return .collision }
        do {
            try FileManager.default.moveItem(at: url, to: dest)
        } catch {
            // The pre-check above covers the common case; treat anything else as a collision
            // (locked, in use, or a race) so the user gets a useful message either way.
            return .collision
        }
        refresh()
        return .success
    }
}
