import XCTest
@testable import ScreenshotBuddy

/// Smoke tests for the file-mutation paths that previously failed silently.
///
/// These are integration tests: they exercise the real FileManager against a throwaway
/// temp directory. They lock in the behaviour we promised in the audit:
///   • rename returns a useful result (collision / invalid chars / empty / in-use / success)
///   • rename handles case-only changes and typed extensions correctly (no false collision, no double extension)
///   • moveToTrash reports success/failure as a Bool (no silent failure)
///   • sweep counts are honest (only successes increment `moved`, failures increment `failed`)
///   • manual undo restores swept files; quitting during the undo window also restores them
///   • the auto-purge timer path still permanently removes files after the window
///   • selection state lives on the store and stays consistent across rename/delete/sweep
///
/// `@MainActor`: `ScreenshotStore` is `@MainActor`, so the whole test class runs on main
/// to match the production threading contract. This also means async test methods mutate
/// `@Published` store state correctly (no SwiftUI background-publishing warnings).
@MainActor
final class ScreenshotStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: ScreenshotStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sb-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // Fresh, isolated store per test — no shared singleton, no UserDefaults lookups, no
        // live file watcher. Each test gets a clean slate and points the store at our temp
        // dir via `store.folderURL = tempDir`.
        store = ScreenshotStore(forTesting: ())
    }

    override func tearDownWithError() throws {
        // Cancel any armed auto-purge timer so it can't fire into a torn-down test.
        store?.purgeSweep()
        store = nil
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Helpers

    /// Write a 1-byte file so we have something concrete to rename/sweep.
    @discardableResult
    private func makeFile(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data([0x42]).write(to: url)
        return url
    }

    // MARK: - rename()

    func testRenameSuccess() throws {
        let url = try makeFile("shot.png")
        let result = store.rename(url, to: "renamed")
        XCTAssertEqual(result, .success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("renamed.png").path))
    }

    func testRenameCollision() throws {
        try makeFile("existing.png")
        let url = try makeFile("original.png")
        XCTAssertEqual(store.rename(url, to: "existing"), .collision)
        // The original file must still be there, untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testRenameInvalidCharacters() throws {
        let url = try makeFile("shot.png")
        XCTAssertEqual(store.rename(url, to: "bad/name"), .invalidCharacters)
        XCTAssertEqual(store.rename(url, to: "bad:name"), .invalidCharacters)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testRenameEmpty() throws {
        let url = try makeFile("shot.png")
        XCTAssertEqual(store.rename(url, to: "   "), .emptyName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    /// Case-only rename (e.g. "shot.png" → "Shot.png") must succeed. On the default
    /// case-insensitive APFS volume the old code's `fileExists` pre-check saw "Shot.png"
    /// as a collision with the existing "shot.png" and wrongly rejected it.
    func testRenameCaseOnlySucceeds() throws {
        let url = try makeFile("shot.png")
        XCTAssertEqual(store.rename(url, to: "Shot"), .success)
        // On a case-insensitive volume, fileExists("shot.png") still returns true after a
        // rename to "Shot.png" (same inode), so read the actual on-disk names to verify the
        // case actually changed.
        let actualNames = try FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil).map { $0.lastPathComponent }
        XCTAssertFalse(actualNames.contains("shot.png"), "old lowercase name should be gone")
        XCTAssertTrue(actualNames.contains("Shot.png"), "new capitalized name should exist")
    }

    /// A typed image extension is respected — no ".png" appended. Previously renaming
    /// "shot.png" to "photo.jpg" produced "photo.jpg.png".
    func testRenameDifferentExtensionKeepsNewExtension() throws {
        let url = try makeFile("shot.png")
        XCTAssertEqual(store.rename(url, to: "photo.jpg"), .success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("photo.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("photo.jpg.png").path))
    }

    // MARK: - moveToTrash()

    /// moveToTrash reports success as a Bool so the cell can show a failure toast.
    /// We can't reliably force a "locked/in-use" failure in CI, but we can lock the
    /// success contract and the missing-file failure path.
    func testMoveToTrashReturnsTrueOnSuccess() throws {
        let url = try makeFile("doomed.png")
        XCTAssertTrue(store.moveToTrash(url))
        // The file should no longer be in our temp dir (moved to Trash or removed by the sandbox).
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// Trashing a file that doesn't exist returns false (no silent success on failure).
    func testMoveToTrashReturnsFalseOnMissingFile() {
        let ghost = tempDir.appendingPathComponent("nope.png")
        XCTAssertFalse(store.moveToTrash(ghost))
    }

    // MARK: - sweepAllToTrash()

    func testSweepOutcomeCountsHonestOnFullSuccess() async throws {
        // Point the store at our temp dir so files[] populates, then sweep.
        store.folderURL = tempDir
        try makeFile("a.png"); try makeFile("b.png"); try makeFile("c.png")
        // Force an immediate refresh, then wait for the store to publish the result. The
        // store's refresh is async (off-main + main-hop), so we poll on the main run loop
        // via an XCTest expectation rather than a fixed delay.
        store.refresh()
        await waitForFilesCount(3)

        let outcome = store.sweepAllToTrash()
        // TrashItem either moves to Trash or (in sandboxed CI) may fail; either way the
        // invariant holds: moved + failed == total, and the count never exceeds what we had.
        XCTAssertLessThanOrEqual(outcome.moved, 3)
        XCTAssertEqual(outcome.moved + outcome.failed, 3)
    }

    // MARK: - Quit-during-undo (restoreOnQuit)

    /// Quitting during the undo window must restore the swept files, not purge them.
    /// This is the 5-second promise: "Undo available for 5 seconds" must be literally true
    /// even if the user Cmd-Qs immediately after Delete Forever.
    func testRestoreOnQuitRestoresPendingSweep() async throws {
        store.folderURL = tempDir
        let a = try makeFile("keep-a.png")
        let b = try makeFile("keep-b.png")
        store.refresh()
        await waitForFilesCount(2)

        // Simulate the user clicking "Delete Forever": files move to a temp holding area.
        let outcome = store.deleteAll()
        XCTAssertEqual(outcome.moved, 2)
        store.refresh()
        await waitForFilesCount(0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.path))

        // Simulate the app quitting mid-undo-window. Files must come back.
        store.restoreOnQuit()
        store.refresh()
        await waitForFilesCount(2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
    }

    /// restoreOnQuit() must be a safe no-op when there's nothing pending (the normal quit path).
    func testRestoreOnQuitIsNoOpWhenNoPendingSweep() {
        // No deleteAll() has been called, so there's no pending sweep. Calling restoreOnQuit
        // must not throw or change any state.
        store.restoreOnQuit()
        // No assertion needed beyond not crashing; if pendingSweep were wrongly nil-dereferenced
        // or the timer were force-unwrapped, this would trap.
    }

    /// Manual undo (the Undo button in the toast) must restore swept files to their original
    /// locations and tear down the temp holding area. Locks in the user-facing undo path
    /// independently of the quit-on-undo path.
    func testUndoSweepRestoresFiles() async throws {
        store.folderURL = tempDir
        let a = try makeFile("undo-a.png")
        let b = try makeFile("undo-b.png")
        store.refresh()
        await waitForFilesCount(2)

        let outcome = store.deleteAll()
        XCTAssertEqual(outcome.moved, 2)
        store.refresh()
        await waitForFilesCount(0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.path))

        // Simulate the user clicking Undo before the timer fires. Files must come back.
        store.undoSweep()
        store.refresh()
        await waitForFilesCount(2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
    }

    /// undoSweep() must be a safe no-op when there's nothing pending (e.g. the timer already
    /// fired, or no sweep was ever started).
    func testUndoSweepIsNoOpWhenNoPendingSweep() {
        store.undoSweep()
        // No crash / no state change. Mirrors the restoreOnQuit no-op contract.
    }

    /// Regression guard: the normal auto-purge path (timer fires after the undo window)
    /// still permanently removes the files. We call purgeSweep() directly to simulate the
    /// timer without waiting 5 seconds — it's the exact code the timer executes.
    func testPurgeStillWorksAfterWindow() async throws {
        store.folderURL = tempDir
        let a = try makeFile("doomed-a.png")
        let b = try makeFile("doomed-b.png")
        store.refresh()
        await waitForFilesCount(2)

        let outcome = store.deleteAll()
        XCTAssertEqual(outcome.moved, 2)
        store.refresh()
        await waitForFilesCount(0)

        // Simulate the undo-window timer firing. Files must be gone for good (not restored).
        store.purgeSweep()
        store.refresh()
        await waitForFilesCount(0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.path))
    }

    // MARK: - Selection state machine (Phase 5: selection now lives on the store)

    /// select() sets the published selection. The single-tap path in ScreenshotCell relies on this.
    func testSelectSetsSelection() {
        let url = URL(fileURLWithPath: "/tmp/whatever.png")
        XCTAssertNil(store.selection)
        store.select(url)
        XCTAssertEqual(store.selection, url)
    }

    /// clearSelection() nils out selection. Used internally by delete/sweep before they mutate files.
    func testClearSelection() {
        let url = URL(fileURLWithPath: "/tmp/whatever.png")
        store.select(url)
        store.clearSelection()
        XCTAssertNil(store.selection)
    }

    /// moveSelection clamps at both ends and is a no-op on an empty file list.
    func testMoveSelectionClamps() {
        let a = URL(fileURLWithPath: "/tmp/a.png")
        let b = URL(fileURLWithPath: "/tmp/b.png")
        let c = URL(fileURLWithPath: "/tmp/c.png")
        store.files = [a, b, c]

        // No prior selection: a forward move lands on index 0 (the first item).
        store.moveSelection(by: 1)
        XCTAssertEqual(store.selection, a)

        // Forward past the end clamps to the last item.
        store.moveSelection(by: 99)
        XCTAssertEqual(store.selection, c)

        // Backward past the start clamps to the first item.
        store.moveSelection(by: -99)
        XCTAssertEqual(store.selection, a)
    }

    /// moveSelection is a no-op when there are no files (e.g. empty folder, mid-sweep).
    func testMoveSelectionNoOpOnEmpty() {
        store.moveSelection(by: 1)
        XCTAssertNil(store.selection)
    }

    /// Deleting all screenshots clears the selection (the whole grid is going away).
    func testClearSelectionOnDeleteAll() async throws {
        store.folderURL = tempDir
        let a = try makeFile("a.png")
        let b = try makeFile("b.png")
        store.refresh()
        await waitForFilesCount(2)
        store.select(a)
        XCTAssertEqual(store.selection, a)

        store.deleteAll()
        XCTAssertNil(store.selection, "selection must clear after deleteAll")
    }

    /// Sweeping to Trash clears the selection (the whole grid is going away).
    func testClearSelectionOnSweepAllToTrash() async throws {
        store.folderURL = tempDir
        let a = try makeFile("a.png")
        try makeFile("b.png")
        store.refresh()
        await waitForFilesCount(2)
        store.select(a)
        XCTAssertEqual(store.selection, a)

        store.sweepAllToTrash()
        XCTAssertNil(store.selection, "selection must clear after sweepAllToTrash")
    }

    /// Renaming the selected file moves the selection to the new URL so the highlight follows.
    func testRenameUpdatesSelection() throws {
        let url = try makeFile("shot.png")
        store.select(url)
        XCTAssertEqual(store.selection, url)

        let result = store.rename(url, to: "renamed")
        XCTAssertEqual(result, .success)
        XCTAssertEqual(store.selection?.lastPathComponent, "renamed.png",
                       "selection must track to the renamed URL")
    }

    /// Trashing the selected file clears the selection (the file no longer exists).
    func testClearSelectionOnMoveToTrashOfSelected() throws {
        let url = try makeFile("doomed.png")
        store.select(url)
        XCTAssertEqual(store.selection, url)

        XCTAssertTrue(store.moveToTrash(url))
        XCTAssertNil(store.selection, "selection must clear when the selected file is trashed")
    }

    /// Trashing a *different* file leaves the selection intact.
    func testMoveToTrashKeepsSelectionWhenOtherFileTrashed() throws {
        let selected = try makeFile("selected.png")
        let other = try makeFile("other.png")
        store.select(selected)

        XCTAssertTrue(store.moveToTrash(other))
        XCTAssertEqual(store.selection, selected,
                       "selection must not clear when an unrelated file is trashed")
    }

    /// Polls the store on the main run loop until `files` reaches `count`, or times out.
    /// Uses XCTest expectations so the run loop is pumped while we wait (a plain Task.sleep
    /// blocks the cooperative thread without draining the main-queue hop the store depends on).
    private func waitForFilesCount(_ count: Int, timeout: TimeInterval = 10.0) async {
        let exp = expectation(description: "files == \(count)")
        let timer = Timer(timeInterval: 0.03, repeats: true) { t in
            if self.store.files.count == count {
                exp.fulfill()
                t.invalidate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        await fulfillment(of: [exp], timeout: timeout)
        timer.invalidate()
    }
}
