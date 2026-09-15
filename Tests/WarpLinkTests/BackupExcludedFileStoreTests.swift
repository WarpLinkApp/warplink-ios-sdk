import XCTest
@testable import WarpLink

/// The real gate store, exercised against a temporary directory rather than the
/// host's Application Support directory.
final class BackupExcludedFileStoreTests: XCTestCase {

    private var directory: URL!
    private var store: BackupExcludedFileStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupExcludedFileStoreTests-\(UUID().uuidString)")
        store = BackupExcludedFileStore(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testUnmarkedKeyReadsAsUnmarked() {
        XCTAssertFalse(store.isMarked("gate"))
    }

    func testMarkThenIsMarked() {
        XCTAssertTrue(store.mark("gate"))
        XCTAssertTrue(store.isMarked("gate"))
    }

    func testMarkIsScopedToItsKey() {
        store.mark("gate")
        XCTAssertFalse(store.isMarked("other"))
    }

    func testMarkSurvivesANewStoreOverTheSameDirectory() {
        store.mark("gate")

        // The app relaunched: same container, so the gate is still closed.
        XCTAssertTrue(BackupExcludedFileStore(directory: directory).isMarked("gate"))
    }

    func testClearRemovesTheMark() {
        store.mark("gate")

        XCTAssertTrue(store.clear("gate"))
        XCTAssertFalse(store.isMarked("gate"))
    }

    func testClearOfAnUnmarkedKeySucceeds() {
        // Clearing is a request for a state, not for an event, so a key that was
        // never marked is already in the state the caller asked for.
        XCTAssertTrue(store.clear("gate"))
    }

    func testMarkedDirectoryIsExcludedFromBackup() {
        store.mark("gate")

        let excluded = try? directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
            .isExcludedFromBackup
        XCTAssertEqual(
            excluded, true,
            "a gate that a backup can restore would suppress attribution on the restored device"
        )
    }

    func testUnwritableLocationDegradesInsteadOfThrowing() {
        // A regular file where the directory should be: creating the directory
        // cannot succeed. `Storage` answers a false here with its own fallback,
        // so the SDK must report the failure rather than trap on it.
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("blocker-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: blocker.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: blocker) }

        let blocked = BackupExcludedFileStore(directory: blocker.appendingPathComponent("markers"))

        XCTAssertFalse(blocked.mark("gate"))
        XCTAssertFalse(blocked.isMarked("gate"))
    }
}
