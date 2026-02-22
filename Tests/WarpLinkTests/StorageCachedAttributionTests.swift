import XCTest
@testable import WarpLink

final class StorageCachedAttributionTests: XCTestCase {

    private var storage: Storage!
    private var defaults: UserDefaults!
    private let suiteName = "StorageCachedAttributionTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        storage = Storage(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRoundTripAllFields() {
        let deepLink = WarpLinkDeepLink(
            linkId: "link-123",
            destination: "https://example.com/page",
            deepLinkUrl: "myapp://content/42",
            customParams: ["promo": "summer", "ref": "email"],
            isDeferred: true,
            matchType: .probabilistic,
            matchConfidence: 0.85
        )
        storage.cachedAttribution = deepLink

        let cached = storage.cachedAttribution
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.linkId, "link-123")
        XCTAssertEqual(cached?.destination, "https://example.com/page")
        XCTAssertEqual(cached?.deepLinkUrl, "myapp://content/42")
        XCTAssertTrue(cached?.isDeferred ?? false)
        XCTAssertEqual(cached?.matchType, .probabilistic)
        XCTAssertEqual(cached?.matchConfidence, 0.85)
    }

    func testRoundTripNilOptionalFields() {
        let deepLink = WarpLinkDeepLink(
            linkId: "link-456",
            destination: "https://example.com",
            deepLinkUrl: nil,
            customParams: [:],
            isDeferred: true,
            matchType: nil,
            matchConfidence: nil
        )
        storage.cachedAttribution = deepLink

        let cached = storage.cachedAttribution
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.linkId, "link-456")
        XCTAssertNil(cached?.deepLinkUrl)
        XCTAssertNil(cached?.matchType)
        XCTAssertNil(cached?.matchConfidence)
    }

    func testCustomParamsRoundTrip() {
        let deepLink = WarpLinkDeepLink(
            linkId: "link-789",
            destination: "https://example.com",
            customParams: ["key1": "value1", "key2": "value2"],
            isDeferred: true
        )
        storage.cachedAttribution = deepLink

        let cached = storage.cachedAttribution
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.customParams["key1"] as? String, "value1")
        XCTAssertEqual(cached?.customParams["key2"] as? String, "value2")
    }

    func testEmptyCustomParamsRoundTrip() {
        let deepLink = WarpLinkDeepLink(
            linkId: "link-empty",
            destination: "https://example.com",
            customParams: [:],
            isDeferred: true
        )
        storage.cachedAttribution = deepLink

        let cached = storage.cachedAttribution
        XCTAssertNotNil(cached)
        XCTAssertTrue(cached?.customParams.isEmpty ?? false)
    }

    func testGetterReturnsNilWhenNothingCached() {
        XCTAssertNil(storage.cachedAttribution)
    }

    func testClearAllRemovesCachedAttribution() {
        let deepLink = WarpLinkDeepLink(
            linkId: "link-clear",
            destination: "https://example.com",
            isDeferred: true
        )
        storage.cachedAttribution = deepLink
        XCTAssertNotNil(storage.cachedAttribution)

        storage.clearAll()
        XCTAssertNil(storage.cachedAttribution)
    }

    func testOverwriteCachedAttribution() {
        let first = WarpLinkDeepLink(
            linkId: "link-first",
            destination: "https://first.com",
            isDeferred: true
        )
        storage.cachedAttribution = first
        XCTAssertEqual(storage.cachedAttribution?.linkId, "link-first")

        let second = WarpLinkDeepLink(
            linkId: "link-second",
            destination: "https://second.com",
            deepLinkUrl: "myapp://new",
            isDeferred: true,
            matchType: .deterministic,
            matchConfidence: 1.0
        )
        storage.cachedAttribution = second

        let cached = storage.cachedAttribution
        XCTAssertEqual(cached?.linkId, "link-second")
        XCTAssertEqual(cached?.destination, "https://second.com")
        XCTAssertEqual(cached?.deepLinkUrl, "myapp://new")
        XCTAssertEqual(cached?.matchType, .deterministic)
    }
}
