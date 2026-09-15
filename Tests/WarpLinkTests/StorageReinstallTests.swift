import XCTest
@testable import WarpLink

/// The two-marker split that decides `is_reinstall`.
///
/// The gate ("has attribution completed for THIS install?") must die with the
/// app; the device-seen marker ("has this device ever been attributed?") must
/// outlive it. A reinstall is the state where the second is set and the first
/// is not. Both are faked here so the tests can move each one independently.
final class StorageReinstallTests: XCTestCase {

    private var storage: Storage!
    private var defaults: UserDefaults!
    private var deviceMarker: InMemoryMarkerStore!
    private var installMarker: InMemoryMarkerStore!
    private let suiteName = "StorageReinstallTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        deviceMarker = InMemoryMarkerStore()
        installMarker = InMemoryMarkerStore()
        storage = Storage(
            defaults: defaults,
            markerStore: deviceMarker,
            installMarkerStore: installMarker
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Reinstall detection (is_reinstall)

    func testFirstInstallIsNotAReinstall() {
        XCTAssertFalse(storage.hasDeviceEverCompletedAttribution)
        XCTAssertFalse(storage.isReinstall)
    }

    func testCompletionWritesBothTheGateAndTheDeviceSeenMarker() {
        storage.markAttributionComplete()

        XCTAssertTrue(storage.isAttributionComplete, "the gate must close for this install")
        XCTAssertTrue(
            storage.hasDeviceEverCompletedAttribution,
            "the device must be recorded as attributed for the next install"
        )
    }

    func testSecondLaunchWithinOneInstallIsNotAReinstall() {
        storage.markAttributionComplete()

        // Same install, both stores intact: the gate is closed, so nothing is
        // re-attributed and there is no reinstall to report.
        XCTAssertFalse(relaunched().isReinstall)
    }

    func testReinstallIsDetectedAfterAppDeletion() {
        storage.markAttributionComplete()

        // Deleting the app wipes UserDefaults and the app container (so the
        // gate goes with it) but not the Keychain.
        let reinstalled = afterAppDeletion()

        XCTAssertFalse(reinstalled.isAttributionComplete, "a reinstall must attribute again")
        XCTAssertTrue(reinstalled.isReinstall, "and must report itself as a reinstall")
    }

    func testRestoreFromBackupIsDetectedAsAReinstall() {
        storage.markAttributionComplete()

        // A restore carries UserDefaults and the Keychain onto the new device,
        // but not the backup-excluded gate.
        let restored = Storage(
            defaults: defaults,
            markerStore: deviceMarker,
            installMarkerStore: InMemoryMarkerStore()
        )

        XCTAssertFalse(restored.isAttributionComplete, "a restored install must attribute again")
        XCTAssertTrue(restored.isReinstall)
    }

    func testReinstallWithoutAPriorAttributionIsAFirstInstall() {
        // The device completed nothing before, so an empty durable store means
        // a genuine first install even though every other marker is missing too.
        XCTAssertFalse(afterAppDeletion().isReinstall)
    }

    // MARK: - Legacy <= 1.0.x flag

    // conformance: WL-S15
    func testARestoredLegacyFlagLeavesTheGateOpenAndTheDeviceUnseen() {
        // UserDefaults comes back from a restore. A consumed 1.0.x flag in it
        // proves a check once began somewhere; it says nothing about this
        // install, so the gate stays open and nothing is inferred from it.
        defaults.set(false, forKey: "warplink_first_launch")

        XCTAssertFalse(storage.isAttributionComplete)
        XCTAssertFalse(storage.hasDeviceEverCompletedAttribution)
        XCTAssertFalse(storage.isReinstall)
    }

    func testARestoredCacheWithAnOpenGateIsCleared() {
        storage.markAttributionComplete()
        storage.cachedAttribution = WarpLinkDeepLink(
            linkId: "lnk_old", destination: "https://example.com/old", isDeferred: true
        )

        // A restore brings UserDefaults back and the backup-excluded gate not.
        let restored = Storage(
            defaults: defaults, markerStore: deviceMarker, installMarkerStore: InMemoryMarkerStore()
        )

        XCTAssertNil(restored.cachedAttribution)
    }

    func testAClosedGateSurvivesReconstructionAndKeepsItsCachedMatch() {
        storage.markAttributionComplete()
        storage.cachedAttribution = WarpLinkDeepLink(
            linkId: "lnk_current", destination: "https://example.com/current", isDeferred: true
        )

        // No restore or deletion simulated: this is the same install
        // relaunching, so the gate it closed is still here and its own cache
        // must survive.
        XCTAssertEqual(relaunched().cachedAttribution?.linkId, "lnk_current")
    }

    func testAttemptedMarkerDoesNotSurviveARestore() {
        storage.hasAttemptedAttribution = true

        // A restore brings UserDefaults back and the install store not. The
        // attempted flag describes THIS install's attempts, so it must not
        // come back: the "Retrying" log line would lie on a first launch.
        let restored = Storage(
            defaults: defaults, markerStore: deviceMarker, installMarkerStore: InMemoryMarkerStore()
        )
        XCTAssertFalse(restored.hasAttemptedAttribution)
    }

    // MARK: - Helpers

    /// A new launch of the same install: both stores and the defaults survive.
    private func relaunched() -> Storage {
        Storage(defaults: defaults, markerStore: deviceMarker, installMarkerStore: installMarker)
    }

    /// A reinstall: the app container and its preferences are gone, so the gate
    /// and the defaults start empty while the Keychain marker persists.
    private func afterAppDeletion() -> Storage {
        defaults.removePersistentDomain(forName: suiteName)
        return Storage(
            defaults: defaults,
            markerStore: deviceMarker,
            installMarkerStore: InMemoryMarkerStore()
        )
    }
}
