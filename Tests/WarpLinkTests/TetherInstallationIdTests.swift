import XCTest
@testable import WarpLink

final class TetherInstallationIdTests: XCTestCase {

    private let key = "warplink_installation_id"

    // conformance: WL-S58
    func testOneRandomUUIDIsMadeAndKept() {
        let store = InMemoryMarkerStore()
        let ids = InstallationIdStore(store: store, key: key)
        let first = ids.id
        XCTAssertNotNil(UUID(uuidString: first))
        XCTAssertEqual(ids.id, first)
        XCTAssertEqual(InstallationIdStore(store: store, key: key).id, first)
    }

    // conformance: WL-S58
    func testAReinstallMakesANewId() {
        let first = InstallationIdStore(store: InMemoryMarkerStore(), key: key).id
        let second = InstallationIdStore(store: InMemoryMarkerStore(), key: key).id
        XCTAssertNotEqual(first, second)
    }

    // conformance: WL-S58
    func testAStoredValueThatIsNotAUUIDIsReplaced() {
        let store = InMemoryMarkerStore()
        store.write(key, value: "not-a-uuid")
        let id = InstallationIdStore(store: store, key: key).id
        XCTAssertNotNil(UUID(uuidString: id))
        XCTAssertEqual(store.value(key), id)
    }

    func testAStoreThatCannotWriteStillGivesOneIdForTheProcess() {
        let ids = InstallationIdStore(store: FailingMarkerStore(), key: key)
        XCTAssertEqual(ids.id, ids.id)
    }

    func testClearingMakesTheNextIdNew() {
        let store = InMemoryMarkerStore()
        let ids = InstallationIdStore(store: store, key: key)
        let before = ids.id
        XCTAssertTrue(ids.clear())
        XCTAssertNil(store.value(key))
        XCTAssertNotEqual(ids.id, before)
    }

    func testStorageClearAttributionResetsTheId() {
        let store = Storage(
            defaults: UserDefaults(suiteName: "TetherInstallationIdTests")!,
            markerStore: InMemoryMarkerStore(),
            installMarkerStore: InMemoryMarkerStore()
        )
        let before = store.installationId
        XCTAssertEqual(store.installationId, before)
        store.clearAttribution()
        XCTAssertNotEqual(store.installationId, before)
    }

    func testFileStoreKeepsTheIdOutOfBackups() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tether-id-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BackupExcludedFileStore(directory: directory)
        XCTAssertTrue(store.write(key, value: "abc"))
        XCTAssertEqual(store.value(key), "abc")
        let excluded = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(excluded.isExcludedFromBackup, true)
        XCTAssertTrue(store.clear(key))
        XCTAssertNil(store.value(key))
    }
}
