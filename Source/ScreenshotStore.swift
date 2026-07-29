import AppKit
import UniformTypeIdentifiers

/// Owns the chosen folder, its file list, and all file mutations (sweep, delete, rename).
/// The single source of truth for panel state; views observe it via `@EnvironmentObject`.
///
/// `@MainActor`: every `@Published` mutation must happen on the main thread. All production
/// callers (SwiftUI button/gesture closures, `applicationWillTerminate`, the debounce/timer
/// work items scheduled via `DispatchQueue.main`) already run on main, so this turns an
/// existing convention into a compiler-checked contract.
@MainActor
final class ScreenshotStore: ObservableObject {
    static let shared = ScreenshotStore()

    @Published var folderURL: URL? {
        didSet { refresh() }
    }
    @Published var files: [URL] = []
    @Published var totalBytes: Int64 = 0
    /// The currently selected screenshot (grid highlight / Quick Look anchor). Owned here so
    /// file mutations (rename, delete, sweep) can keep it consistent in one place.
    @Published var selection: URL?
    /// True when the chosen folder can't be read (deleted, renamed, drive unplugged, stale bookmark).
    @Published var accessLost = false

    var reclaimable: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    private var monitor: DispatchSourceFileSystemObject?
    /// The folder path the monitor is currently watching, so we only tear down + rebuild the
    /// dispatch source when the folder actually changes — not on every file-list refresh.
    private var monitoredPath: String?
    /// The folder we currently hold a security-scoped access claim on.
    private var accessedURL: URL?
    private static let bookmarkKey = "folderBookmark"

    /// AppKit bridge to the system Quick Look panel. The store owns selection; this bridge
    /// only drives the panel (open/close/navigate). No global singleton, no shared state.
    private let panel = QuickLookPanelBridge()

    /// Image extensions the panel shows. `nonisolated`: it's a constant value, read from the
    /// off-main refresh closure in `performRefresh` — no reason for it to be main-actor-isolated.
    nonisolated static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif", "bmp", "webp"]

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

    /// Test-only initializer: builds a store without touching UserDefaults or claiming
    /// security-scoped access, so tests get a clean instance per case instead of mutating
    /// `.shared` (which carries bookmark state and a live file watcher across tests).
    /// The folder is then pointed at a throwaway temp dir via `folderURL = …`.
    internal init(forTesting: ()) {
        // No bookmark restore, no monitor — tests drive the store explicitly.
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
    /// Monotonic token so a slow, stale background enumeration can never
    /// overwrite a newer refresh's result.
    private var refreshGeneration = 0

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
    /// The off-main closure captures `folder` (a value type) and computes pure results, then
    /// hops to the main actor to call `applyState`. No `@Published` mutation happens off-main.
    private func performRefresh() {
        pendingRefresh?.cancel(); pendingRefresh = nil
        refreshGeneration += 1
        let generation = refreshGeneration
        guard let folder = folderURL else {
            applyState(files: [], totalBytes: 0, accessLost: false)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: (files: [URL], bytes: Int64, accessLost: Bool)
            do {
                let items = try FileManager.default.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles])
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
                result = (filtered, bytes, false)
            } catch {
                // Folder is unreachable — don't pretend it's empty.
                result = ([], 0, true)
            }
            // Hop to the main actor to publish. The class is @MainActor, so applyState
            // can only be touched from main; the Task enforces that.
            Task { @MainActor [weak self] in
                guard let self, generation == self.refreshGeneration else { return }
                self.applyState(files: result.files, totalBytes: result.bytes, accessLost: result.accessLost)
            }
        }
    }

    /// Single main-actor entry point for mutating published state. Called only from
    /// `performRefresh` (which hops to main via a `Task { @MainActor }`) and from `init`.
    private func applyState(files: [URL], totalBytes: Int64, accessLost: Bool) {
        self.files = files
        self.totalBytes = totalBytes
        self.accessLost = accessLost
        startMonitoring()
    }

    /// (Re)start the filesystem watcher. Only called from `applyState` (always on main) and
    /// `init`, so no extra synchronization is needed. Cheap to call repeatedly: if the folder
    /// hasn't changed since the last call, it's a no-op, so bursts of file-watcher events
    /// don't churn file descriptors + dispatch sources on the main thread.
    private func startMonitoring() {
        let path = folderURL?.path
        // Same folder as before — leave the existing source in place.
        if path == monitoredPath, monitor != nil { return }
        // Folder changed (or cleared): tear down the old source before building a new one.
        monitor?.cancel()
        monitor = nil
        monitoredPath = path
        guard path != nil, let folder = folderURL else { return }
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
        // `folderURL`'s didSet triggers a refresh that clears the monitor via startMonitoring,
        // but be explicit so reset() is self-contained.
        monitor?.cancel()
        monitor = nil
        monitoredPath = nil
    }

    /// Moves every screenshot to the macOS Trash (recoverable the normal way).
    /// Returns how many moved and how many couldn't (so the UI can surface partial failures).
    @discardableResult
    func sweepAllToTrash() -> SweepOutcome {
        // The whole folder is being cleared — selection and any open preview are now stale.
        clearSelection()
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
        // The whole folder is being cleared — selection and any open preview are now stale.
        clearSelection()
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

    /// Called when the app is quitting during the undo window. Honors the 5-second promise
    /// ("Undo available for 5 seconds"): instead of purging, restores the swept files to
    /// their original locations. Safe no-op if there's no pending sweep.
    ///
    /// Note: runs synchronously from `applicationWillTerminate`; `undoSweep()` does only
    /// synchronous FileManager work, so the restore completes before the process exits.
    /// If an individual restore fails (e.g. the original folder is gone) the file is left
    /// in the temp dir, which macOS reaps later — no worse than the prior purge-on-quit.
    func restoreOnQuit() {
        guard pendingSweep != nil else { return }
        undoSweep()
    }

    /// Move a single file to the macOS Trash (recoverable), keeping per-file delete consistent
    /// with the safe bulk sweep. Returns true on success, false if the file couldn't be moved
    /// (locked, in use, sandboxed, etc.) so the caller can surface the failure instead of
    /// silently leaving the file in place.
    @discardableResult
    func moveToTrash(_ url: URL) -> Bool {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            return false
        }
        // If we just trashed the selected/previewed file, drop the selection and dismiss any
        // open Quick Look panel so it never points at a deleted URL.
        if selection == url {
            clearSelection()
        }
        refresh()
        return true
    }

    /// Why a rename might not have applied.
    enum RenameResult: Equatable {
        case success
        case emptyName
        case collision          // a different file with that name already exists
        case invalidCharacters  // name contains / or :
        case inUse              // move failed for another reason (locked, in use, permissions, …)
    }

    func rename(_ url: URL, to newName: String) -> RenameResult {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return .emptyName }
        // macOS forbids "/" in filenames; ":" is the legacy HFS separator and shows as "/" in Finder.
        if name.contains("/") || name.contains(":") { return .invalidCharacters }
        // Respect any typed image extension (not just the current one); otherwise append the
        // current one. Prevents "shot.png" → "photo.jpg" from producing "photo.jpg.png".
        let lowerName = name.lowercased()
        let alreadyHasImageExt = Self.imageTypes.contains { ext in lowerName.hasSuffix("." + ext) }
        let finalName = alreadyHasImageExt ? name : name + "." + url.pathExtension
        let dest = url.deletingLastPathComponent().appendingPathComponent(finalName)
        // A case-only change (e.g. "shot.png" → "Shot.png") is the same file on a
        // case-insensitive volume, so fileExists would wrongly flag it as a collision.
        // Detect it via case-insensitive path equality and let the move proceed.
        let isCaseOnlyChange =
            dest.standardizedFileURL.path.lowercased() == url.standardizedFileURL.path.lowercased()
            && dest.path != url.path
        let collisionPreCheck = !isCaseOnlyChange
            && dest != url
            && FileManager.default.fileExists(atPath: dest.path)
        if collisionPreCheck { return .collision }
        do {
            try FileManager.default.moveItem(at: url, to: dest)
        } catch {
            // Distinguish a genuine collision (caught by the pre-check above) from a move that
            // failed for another reason (locked, in use, permissions, race) so the message is honest.
            return collisionPreCheck ? .collision : .inUse
        }
        // Keep selection in sync if the renamed file was selected, and refresh the Quick Look
        // panel's item list if it's open so it previews the new URL instead of the old one.
        if selection == url {
            selection = dest
        }
        panel.refreshItems(to: files, current: selection)
        refresh()
        return .success
    }

    // MARK: - Selection + Quick Look

    /// Set the selection without affecting the Quick Look panel (used on single-tap).
    func select(_ url: URL) {
        selection = url
    }

    /// Clear the selection and dismiss any open Quick Look panel.
    func clearSelection() {
        selection = nil
        panel.closeIfOpen()
    }

    /// Open the Quick Look panel at `url` if closed, or close it if open. Updates selection.
    func toggleQuickLook(_ url: URL) {
        selection = url
        panel.toggle(url: url, in: files)
    }

    /// Move the selection by `delta` positions within `files` (clamped). Advances the Quick
    /// Look panel's current index if it's open. No-op when there are no files.
    func moveSelection(by delta: Int) {
        guard !files.isEmpty else { return }
        let current = selection.flatMap { files.firstIndex(of: $0) } ?? -delta
        let next = min(max(current + delta, 0), files.count - 1)
        selection = files[next]
        panel.setPanelIndex(next)
    }
}
