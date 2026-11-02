import XCTest
@testable import WarpLink

/// Test and live state share one device, one set of defaults and one pair of
/// marker stores, and must never see each other.
final class StorageEnvironmentTests: XCTestCase {

    private var defaults: UserDefaults!
    private var deviceMarkers: InMemoryMarkerStore!
    private var installMarkers: InMemoryMarkerStore!
    private let suiteName = "StorageEnvironmentTests"

    private let link = WarpLinkDeepLink(
        linkId: "link-1", destination: "https://example.com", deepLinkUrl: nil,
        customParams: [:], isDeferred: true, matchType: .deterministic, matchConfidence: nil
    )

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        deviceMarkers = InMemoryMarkerStore()
        installMarkers = InMemoryMarkerStore()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func storage(_ environment: KeyEnvironment) -> Storage {
        Storage(
            environment: environment, defaults: defaults,
            markerStore: deviceMarkers, installMarkerStore: installMarkers
        )
    }

    /// Everything attribution-related, written the way a completed check does.
    private func completeAttribution(_ storage: Storage) {
        storage.hasAttemptedAttribution = true
        storage.markAttributionComplete()
        storage.cachedAttribution = link
        storage.apiKeyValidatedAt = Date()
        storage.cachedDomains = ["links.acme.com"]
    }

    // MARK: - Upgrade from 1.2.0

    func testProductionReadsTheNames1_2_0Wrote() throws {
        defaults.set(Date().timeIntervalSince1970, forKey: "warplink_api_key_validated_at")
        defaults.set(["links.acme.com"], forKey: "warplink_cached_domains")
        defaults.set(try JSONEncoder().encode(link), forKey: "warplink_cached_attribution")
        installMarkers.mark("warplink_attribution_complete")
        installMarkers.mark("warplink_attribution_attempted")
        deviceMarkers.mark("warplink_attribution_complete")

        let upgraded = storage(.production)

        XCTAssertTrue(upgraded.isApiKeyValidationCacheValid)
        XCTAssertEqual(upgraded.cachedDomains, ["links.acme.com"])
        XCTAssertEqual(upgraded.cachedAttribution?.linkId, "link-1")
        XCTAssertTrue(upgraded.isAttributionComplete)
        XCTAssertTrue(upgraded.hasAttemptedAttribution)
        XCTAssertTrue(upgraded.hasDeviceEverCompletedAttribution)
    }

    func testProductionReadsThe1_2_0CompletionFallback() {
        defaults.set(true, forKey: "warplink_attribution_complete_fallback")

        XCTAssertTrue(storage(.production).isAttributionComplete)
    }

    func testProductionWritesTheNames1_2_0Reads() {
        completeAttribution(storage(.production))

        XCTAssertNotNil(defaults.data(forKey: "warplink_cached_attribution"))
        XCTAssertNotNil(defaults.object(forKey: "warplink_api_key_validated_at"))
        XCTAssertNotNil(defaults.object(forKey: "warplink_cached_domains"))
        XCTAssertTrue(installMarkers.isMarked("warplink_attribution_complete"))
        XCTAssertTrue(installMarkers.isMarked("warplink_attribution_attempted"))
        XCTAssertTrue(deviceMarkers.isMarked("warplink_attribution_complete"))
    }

    // MARK: - Isolation

    func testTestCannotReadAnyLiveState() {
        completeAttribution(storage(.production))

        let test = storage(.test)

        XCTAssertFalse(test.isAttributionComplete)
        XCTAssertFalse(test.hasAttemptedAttribution)
        XCTAssertFalse(test.hasDeviceEverCompletedAttribution)
        XCTAssertNil(test.cachedAttribution)
        XCTAssertNil(test.apiKeyValidatedAt)
        XCTAssertEqual(test.cachedDomains, [])
    }

    func testLiveCannotReadAnyTestState() {
        completeAttribution(storage(.test))

        let live = storage(.production)

        XCTAssertFalse(live.isAttributionComplete)
        XCTAssertFalse(live.hasAttemptedAttribution)
        XCTAssertFalse(live.hasDeviceEverCompletedAttribution)
        XCTAssertNil(live.cachedAttribution)
        XCTAssertNil(live.apiKeyValidatedAt)
        XCTAssertEqual(live.cachedDomains, [])
    }

    func testTestClearLeavesLiveStateIntact() {
        completeAttribution(storage(.production))
        completeAttribution(storage(.test))

        storage(.test).clearAttribution()

        let live = storage(.production)
        XCTAssertTrue(live.isAttributionComplete)
        XCTAssertTrue(live.hasAttemptedAttribution)
        XCTAssertTrue(live.hasDeviceEverCompletedAttribution)
        XCTAssertEqual(live.cachedAttribution?.linkId, "link-1")
        XCTAssertTrue(live.isApiKeyValidationCacheValid)
        XCTAssertEqual(live.cachedDomains, ["links.acme.com"])
    }

    func testCreatingTestStorageDoesNotRemoveLiveLegacyKeys() {
        defaults.set(true, forKey: "warplink_first_launch")

        _ = storage(.test)

        XCTAssertNotNil(defaults.object(forKey: "warplink_first_launch"))
    }

    // MARK: - Reset

    func testClearAttributionOpensTheGateAndForgetsTheDevice() {
        let test = storage(.test)
        completeAttribution(test)

        test.clearAttribution()

        XCTAssertFalse(test.isAttributionComplete)
        XCTAssertFalse(test.hasAttemptedAttribution)
        XCTAssertFalse(test.hasDeviceEverCompletedAttribution)
        XCTAssertFalse(test.isReinstall, "a cleared device is a first install, not a reinstall")
        XCTAssertNil(test.cachedAttribution)
    }

    func testClearAttributionOpensTheDefaultsFallbackGate() {
        let test = storage(.test)
        defaults.set(true, forKey: "warplink_attribution_complete_fallback_test")
        XCTAssertTrue(test.isAttributionComplete)

        test.clearAttribution()

        XCTAssertFalse(test.isAttributionComplete)
    }

    func testClearAttributionKeepsKeyValidationAndDomains() {
        let test = storage(.test)
        completeAttribution(test)

        test.clearAttribution()

        XCTAssertTrue(test.isApiKeyValidationCacheValid)
        XCTAssertEqual(test.cachedDomains, ["links.acme.com"])
    }
}
