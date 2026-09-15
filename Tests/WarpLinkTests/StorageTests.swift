import XCTest
@testable import WarpLink

final class StorageTests: XCTestCase {

    private var storage: Storage!
    private var defaults: UserDefaults!
    /// Stands in for the Keychain: survives an app delete and a restore.
    private var deviceMarker: InMemoryMarkerStore!
    /// Stands in for the backup-excluded file: dies with the app.
    private var installMarker: InMemoryMarkerStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "StorageTests")!
        defaults.removePersistentDomain(forName: "StorageTests")
        deviceMarker = InMemoryMarkerStore()
        installMarker = InMemoryMarkerStore()
        storage = Storage(
            defaults: defaults,
            markerStore: deviceMarker,
            installMarkerStore: installMarker
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "StorageTests")
        super.tearDown()
    }

    // MARK: - API key validation cache

    func testApiKeyValidatedAtDefaultNil() {
        XCTAssertNil(storage.apiKeyValidatedAt)
    }

    func testApiKeyValidatedAtRoundTrips() {
        let now = Date()
        storage.apiKeyValidatedAt = now
        let stored = storage.apiKeyValidatedAt
        XCTAssertNotNil(stored)
        XCTAssertEqual(stored!.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
    }

    func testValidationCacheValidWithin24Hours() {
        storage.apiKeyValidatedAt = Date()
        XCTAssertTrue(storage.isApiKeyValidationCacheValid)
    }

    func testValidationCacheExpiredAfter24Hours() {
        storage.apiKeyValidatedAt = Date().addingTimeInterval(-86401)
        XCTAssertFalse(storage.isApiKeyValidationCacheValid)
    }

    // MARK: - Attribution lifecycle (attempted vs completed)

    func testAttributionNotCompleteByDefault() {
        XCTAssertFalse(storage.isAttributionComplete)
    }

    func testMarkAttributionCompleteSurvivesRelaunchWithinOneInstall() {
        storage.markAttributionComplete()
        XCTAssertTrue(storage.isAttributionComplete)

        // A fresh Storage over the SAME stores (simulating a relaunch) still
        // sees the gate closed, so the launch does not re-attribute.
        XCTAssertTrue(relaunched().isAttributionComplete)
    }

    func testHasAttemptedAttributionDefaultsFalse() {
        XCTAssertFalse(storage.hasAttemptedAttribution)
    }

    func testHasAttemptedAttributionRoundTrips() {
        storage.hasAttemptedAttribution = true
        XCTAssertTrue(storage.hasAttemptedAttribution)
    }

    func testHasAttemptedAttributionSurvivesRelaunchWithinOneInstall() {
        storage.hasAttemptedAttribution = true

        // A fresh Storage over the SAME stores (simulating a relaunch) still
        // sees the attempt, so a retry after a relaunch is not misreported as
        // a first attempt.
        XCTAssertTrue(relaunched().hasAttemptedAttribution)
    }

    func testAttemptedAndCompletedAreIndependent() {
        // An attempt that failed leaves attempted=true, completed=false → retry.
        storage.hasAttemptedAttribution = true
        XCTAssertFalse(storage.isAttributionComplete)
        XCTAssertTrue(storage.hasAttemptedAttribution)
    }

    func testMarkAttributionCompleteFallsBackWhenInstallStoreCannotWrite() {
        let unusable = Storage(
            defaults: defaults,
            markerStore: deviceMarker,
            installMarkerStore: FailingMarkerStore()
        )
        unusable.markAttributionComplete()
        XCTAssertTrue(unusable.isAttributionComplete)

        // Next launch of the SAME install: the UserDefaults fallback still
        // holds, so the deferred result is never re-delivered.
        let relaunchedUnusable = Storage(
            defaults: defaults,
            markerStore: deviceMarker,
            installMarkerStore: FailingMarkerStore()
        )
        XCTAssertTrue(relaunchedUnusable.isAttributionComplete)
    }

    func testFallbackMarkerNotWrittenWhenInstallStoreWorks() {
        storage.markAttributionComplete()

        // The gate lives in the install store, so the UserDefaults fallback
        // must stay untouched. It is the one part of the gate a backup restore
        // could carry over, so it is written only when there is no alternative.
        XCTAssertNil(defaults.object(forKey: "warplink_attribution_complete_fallback"))
    }

    // MARK: - Domains

    func testCachedDomainsDefaultEmpty() {
        XCTAssertTrue(storage.cachedDomains.isEmpty)
    }

    func testCachedDomainsRoundTrip() {
        storage.cachedDomains = ["aplnk.to", "go.acme.com"]
        XCTAssertEqual(storage.cachedDomains, ["aplnk.to", "go.acme.com"])
    }

    // MARK: - clearAll

    func testClearAllResetsEverything() {
        storage.apiKeyValidatedAt = Date()
        storage.hasAttemptedAttribution = true
        storage.markAttributionComplete()
        storage.cachedDomains = ["go.acme.com"]

        storage.clearAll()

        XCTAssertNil(storage.apiKeyValidatedAt)
        XCTAssertFalse(storage.hasAttemptedAttribution)
        XCTAssertFalse(storage.isAttributionComplete)
        XCTAssertFalse(
            storage.hasDeviceEverCompletedAttribution,
            "clearAll is the test hook for a pristine device, so it must clear the durable marker too"
        )
        XCTAssertTrue(storage.cachedDomains.isEmpty)
    }

    func testClearAllResetsFallbackCompletionMarker() {
        let unusable = Storage(
            defaults: defaults,
            markerStore: deviceMarker,
            installMarkerStore: FailingMarkerStore()
        )
        unusable.markAttributionComplete()

        unusable.clearAll()

        XCTAssertFalse(unusable.isAttributionComplete)
    }

    // MARK: - 1.0.x leftovers

    func testLegacyOneDotZeroKeysArePurgedOnConstruction() {
        let legacy = [
            "warplink_first_launch",
            "warplink_has_cached_attribution",
            "warplink_cached_link_id",
            "warplink_cached_destination",
            "warplink_cached_deep_link_url",
            "warplink_cached_is_deferred",
            "warplink_cached_match_type",
            "warplink_cached_match_confidence",
            "warplink_cached_custom_params",
        ]
        for key in legacy { defaults.set("stale", forKey: key) }

        _ = Storage(
            defaults: defaults,
            markerStore: InMemoryMarkerStore(),
            installMarkerStore: InMemoryMarkerStore()
        )

        // Nothing reads them any more. Left behind, they sit in the plist for
        // the life of the install and get carried through every backup.
        for key in legacy { XCTAssertNil(defaults.object(forKey: key), key) }
    }

    // MARK: - Helpers

    /// A new launch of the same install: both stores and the defaults survive.
    private func relaunched() -> Storage {
        Storage(defaults: defaults, markerStore: deviceMarker, installMarkerStore: installMarker)
    }
}
