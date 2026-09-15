import XCTest
@testable import WarpLink

/// The iOS half of the same 1.0.x flag.
///
/// iOS never gated on it, so an upgrade here is not locked out. What it does
/// instead is inherit a device-seen marker from the flag, which tags the
/// upgrade's own first attribution as a reinstall of an install that 1.0.x
/// never recorded. Same false premise, quieter symptom.
final class LegacyUpgradeAttributionTests: XCTestCase {

    private var storage: Storage!
    private var defaults: UserDefaults!
    private var deviceMarker: InMemoryMarkerStore!
    private var installMarker: InMemoryMarkerStore!
    private let suiteName = "LegacyUpgradeAttributionTests"

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

    func testAConsumedLegacyFlagDoesNotMarkTheDeviceSeen() {
        defaults.set(false, forKey: "warplink_first_launch")

        XCTAssertFalse(storage.hasDeviceEverCompletedAttribution)
    }

    func testAnInPlaceUpgradeIsAttributedAsAFirstInstall() {
        defaults.set(false, forKey: "warplink_first_launch")

        // The flag marks a check that started, not an install that was
        // recorded. Reporting this attribution as a reinstall claims a first
        // install that does not exist in the data.
        XCTAssertFalse(storage.isReinstall)
    }

    func testReadingTheLegacyFlagWritesNoDurableMarker() {
        defaults.set(false, forKey: "warplink_first_launch")
        _ = storage.hasDeviceEverCompletedAttribution

        // The device-seen marker is Keychain-backed and outlives an app delete.
        // Deriving it from the flag makes the mislabel permanent.
        XCTAssertFalse(deviceMarker.isMarked("warplink_attribution_complete"))
    }
}
