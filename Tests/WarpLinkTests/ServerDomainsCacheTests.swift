import XCTest
@testable import WarpLink

/// Deleting the cache write in applyServerDomains kept the suite green. The
/// next offline cold launch would then not resolve a custom-domain link at all.
final class ServerDomainsCacheTests: XCTestCase {

    override func setUp() {
        super.setUp()
        WarpLink.reset()
    }

    override func tearDown() {
        WarpLink.reset()
        super.tearDown()
    }

    private func freshStorage() -> Storage {
        let defaults = UserDefaults(suiteName: "ServerDomainsCacheTests")!
        defaults.removePersistentDomain(forName: "ServerDomainsCacheTests")
        return Storage(
            defaults: defaults,
            markerStore: InMemoryMarkerStore(),
            installMarkerStore: InMemoryMarkerStore()
        )
    }

    func testAServerAnswerIsCachedForTheNextOfflineLaunch() {
        let store = freshStorage()
        WarpLink.applyServerDomains(["go.acme.com"], storage: store)
        XCTAssertEqual(store.cachedDomains, ["go.acme.com"])

        // The mirror of the preserved direction asserted below: a guard that
        // skipped the write whenever a cache already existed would keep "an
        // empty answer keeps the cache" green while freezing the cache for the
        // life of the install. A real answer must land on top of an older one.
        WarpLink.applyServerDomains(["moved.acme.com"], storage: store)
        XCTAssertEqual(store.cachedDomains, ["moved.acme.com"])
    }

    func testAnEmptyAnswerDoesNotClearAGoodCache() {
        let store = freshStorage()
        store.cachedDomains = ["keep.me"]
        WarpLink.applyServerDomains([], storage: store)
        XCTAssertEqual(store.cachedDomains, ["keep.me"])
    }
}
