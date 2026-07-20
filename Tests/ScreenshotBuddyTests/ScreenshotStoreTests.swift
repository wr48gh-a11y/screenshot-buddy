import XCTest
@testable import ScreenshotBuddy

/// Smoke tests for the file-mutation paths that previously failed silently.
///
/// These are integration tests: they exercise the real FileManager against a throwaway
/// temp directory. They lock in the behaviour we promised in the audit:
///   • rename returns a useful result (collision / invalid chars / empty / success)
///   • sweep counts are honest (only successes increment `moved`, failures increment `failed`)
final class ScreenshotStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: ScreenshotStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sb-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // The store singleton is fine here — we point it at our temp dir and exercise only
        // the file-mutation methods. Its init-time bookmark lookup is dormant without a key.
        store = ScreenshotStore.shared
    }

    override func tearDownWithError() throws {
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

    // MARK: - sweepAllToTrash()

    func testSweepOutcomeCountsHonestOnFullSuccess() async throws {
        // Point the store at our temp dir so files[] populates, then sweep.
        store.folderURL = tempDir
        try makeFile("a.png"); try makeFile("b.png"); try makeFile("c.png")
        // Force an immediate refresh, then wait for the store to publish the result. The
        // store's refresh is async (off-main + main-hop), so we poll on the main run loop
        // via an XCTest expectation rather than a fixed delay.
        store.refresh()
        await waitForFilesCount(3, timeout: 3.0)

        let outcome = store.sweepAllToTrash()
        // TrashItem either moves to Trash or (in sandboxed CI) may fail; either way the
        // invariant holds: moved + failed == total, and the count never exceeds what we had.
        XCTAssertLessThanOrEqual(outcome.moved, 3)
        XCTAssertEqual(outcome.moved + outcome.failed, 3)
    }

    /// Polls the store on the main run loop until `files` reaches `count`, or times out.
    /// Uses XCTest expectations so the run loop is pumped while we wait (a plain Task.sleep
    /// blocks the cooperative thread without draining the main-queue hop the store depends on).
    private func waitForFilesCount(_ count: Int, timeout: TimeInterval) async {
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
