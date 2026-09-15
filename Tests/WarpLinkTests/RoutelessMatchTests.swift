import XCTest
@testable import WarpLink

private class RoutelessMockProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// The deferred check is allowed to run once per install, and the gate that
/// enforces that is written on any 200. A match the SDK cannot route is not a
/// definitive answer: it names no link and carries no destination, so
/// `deferredLink(from:)` throws it away and the host is told nothing matched.
/// Consuming the one attempt on it ends attribution for the whole install.
///
/// The server emits exactly this body from the device_id branch when the link an
/// install was attributed to has since been deleted.
final class RoutelessMatchTests: XCTestCase {

    private let testApiKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        testDefaults = UserDefaults(suiteName: "RoutelessMatchTests")!
        testDefaults.removePersistentDomain(forName: "RoutelessMatchTests")
        URLProtocol.registerClass(RoutelessMockProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(RoutelessMockProtocol.self)
        RoutelessMockProtocol.requestHandler = nil
        testDefaults.removePersistentDomain(forName: "RoutelessMatchTests")
        WarpLink.reset()
        super.tearDown()
    }

    func testRoutelessMatchLeavesTheGateOpen() {
        let store = configureWithMockStorage()
        routelessAttributionResponse(Counter())

        let exp = expectation(description: "completion")
        WarpLink.checkDeferredDeepLink { _ in exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertFalse(
            store.isAttributionComplete,
            "a response with no link and no destination is not a definitive answer"
        )
    }

    /// Every shape `deferredLink(from:)` must refuse, one at a time.
    ///
    /// Each is exercised on its own because the guards mask each other: a body
    /// with both `link_id` and `destination_url` null is rejected by the link
    /// check before the destination check is ever reached, so testing only that
    /// body leaves the other guards unverified. Nothing here is a shape the
    /// server can emit; the SDK must not depend on that to stay correct.
    func testEveryUnusableShapeIsRefused() {
        for (label, body, closesGate) in Self.unusableBodies {
            WarpLink.reset()
            testDefaults.removePersistentDomain(forName: "RoutelessMatchTests")
            let store = configureWithMockStorage()
            respond(withAttributionJSON: body, counting: Counter())

            let exp = expectation(description: label)
            let received = Box<WarpLinkDeepLink>()
            WarpLink.checkDeferredDeepLink { result in
                if case .success(let link) = result { received.value = link }
                exp.fulfill()
            }
            waitForExpectations(timeout: 2)

            XCTAssertNil(received.value, "\(label): should not be routed")
            // Unusable and definitive are different questions. A server that
            // says `matched: false` has answered, whatever else it sent; a
            // server that claims a match it cannot describe has not.
            XCTAssertEqual(
                store.isAttributionComplete, closesGate,
                "\(label): wrong gate state"
            )
        }
    }

    func testRoutelessMatchIsRetriedOnTheNextLaunch() {
        _ = configureWithMockStorage()
        let requests = Counter()
        routelessAttributionResponse(requests)

        let first = expectation(description: "first check")
        WarpLink.checkDeferredDeepLink { _ in first.fulfill() }
        waitForExpectations(timeout: 2)
        XCTAssertEqual(requests.value, 1, "precondition: the first check asked once")

        // The next launch of the same install.
        let second = expectation(description: "second check")
        WarpLink.checkDeferredDeepLink { _ in second.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(
            requests.value, 2,
            "the install has never been attributed, so the check must run again"
        )
    }

    func testARetriedCheckCanStillBeAttributed() {
        _ = configureWithMockStorage()
        routelessAttributionResponse(Counter())

        let first = expectation(description: "first check")
        WarpLink.checkDeferredDeepLink { _ in first.fulfill() }
        waitForExpectations(timeout: 2)

        // The server now has a routable answer for this device.
        matchedAttributionResponse()

        let second = expectation(description: "second check")
        let received = Box<WarpLinkDeepLink>()
        WarpLink.checkDeferredDeepLink { result in
            if case .success(let link) = result { received.value = link }
            second.fulfill()
        }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(received.value?.linkId, "link-abc-123")
        XCTAssertEqual(received.value?.destination, "https://example.com/42")
    }

    /// The cost of leaving the gate open: the auto check now runs on every
    /// launch instead of once. That is only acceptable because a result the host
    /// cannot use never reaches `onLink`, so the extra runs stay silent. A
    /// spurious event per launch would be a worse bug than the one being fixed.
    func testRepeatedAutoChecksStaySilentToTheHost() {
        let sink = Counter()
        let store = configureWithMockStorage(onLink: { _ in sink.increment() })
        let requests = Counter()
        routelessAttributionResponse(requests)

        for _ in 0..<3 {
            let exp = expectation(description: "auto check")
            WarpLink.checkDeferredDeepLink { result in
                WarpLink.dispatchToOnLink(result)
                exp.fulfill()
            }
            waitForExpectations(timeout: 2)
        }

        XCTAssertEqual(requests.value, 3, "every launch retries, none is gated")
        XCTAssertFalse(store.isAttributionComplete)
        XCTAssertEqual(sink.value, 0, "nothing routable, so nothing to dispatch")
    }

    /// A genuine no-match is still definitive, and must still close the gate.
    /// Without this, a fix that simply stopped writing the gate would trade one
    /// defect for a re-fire on every launch.
    func testAConfirmedNoMatchStillClosesTheGate() {
        let store = configureWithMockStorage()
        RoutelessMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            guard request.url?.path.contains("attribution") == true else {
                return (response, Data())
            }
            let data = try JSONSerialization.data(withJSONObject: ["matched": false])
            return (response, data)
        }

        let exp = expectation(description: "completion")
        WarpLink.checkDeferredDeepLink { _ in exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertTrue(store.isAttributionComplete)
    }

    // MARK: - Helpers

    /// `matched: true` with nothing to route to: what the device_id branch
    /// returns once the install's link has been deleted.
    private static let routelessAttributionJSON: [String: Any] = [
        "matched": true,
        "match_type": "probabilistic",
        "match_confidence": 0.85,
        "match_guaranteed": false,
        "link_id": NSNull(),
        "deep_link_url": NSNull(),
        "destination_url": NSNull(),
        "custom_params": [String: Any](),
        "install_id": "inst-456",
        "app_id": NSNull(),
    ]

    /// A body that says `matched` but that the SDK cannot act on, one variant
    /// per guard in `deferredLink(from:)`, plus a `matched: false` that carries
    /// routing anyway (the flag is authoritative, not the fields beside it).
    private static let unusableBodies: [(String, [String: Any], Bool)] = [
        ("no link and no destination", routelessAttributionJSON, false),
        (
            "a link with no destination",
            merged(routelessAttributionJSON, ["link_id": "link-abc-123"]),
            false
        ),
        (
            "a destination with no link",
            merged(
                routelessAttributionJSON,
                ["destination_url": "https://example.com/42"]
            ),
            false
        ),
        (
            "routing on an explicit no-match",
            merged(matchedAttributionJSON, ["matched": false]),
            true
        ),
    ]

    private static func merged(
        _ base: [String: Any], _ overrides: [String: Any]
    ) -> [String: Any] {
        base.merging(overrides) { _, new in new }
    }

    private static let matchedAttributionJSON: [String: Any] = [
        "matched": true,
        "match_type": "probabilistic",
        "match_confidence": 0.85,
        "link_id": "link-abc-123",
        "deep_link_url": "myapp://content/42",
        "destination_url": "https://example.com/42",
        "custom_params": ["promo": "summer"],
        "install_id": "inst-456",
    ]

    private func routelessAttributionResponse(_ requests: Counter) {
        respond(withAttributionJSON: Self.routelessAttributionJSON, counting: requests)
    }

    private func matchedAttributionResponse() {
        respond(withAttributionJSON: Self.matchedAttributionJSON, counting: Counter())
    }

    private func respond(withAttributionJSON json: [String: Any], counting requests: Counter) {
        RoutelessMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            guard request.url?.path.contains("attribution") == true else {
                return (response, Data())
            }
            requests.increment()
            return (response, try JSONSerialization.data(withJSONObject: json))
        }
    }

    /// Ephemeral defaults and in-memory markers, so the test touches neither the
    /// real Keychain nor the host's Application Support directory.
    private func configureWithMockStorage(
        onLink: (@Sendable (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void)? = nil
    ) -> Storage {
        RoutelessMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        // Auto behaviour off so configure() cannot fire a check before the
        // deterministic storage below is injected; the sink is still wired, so a
        // test can drive the auto dispatch path itself.
        WarpLink.configure(
            apiKey: testApiKey,
            options: WarpLinkOptions(
                autoDeepLinkHandling: false, autoDeferredCheck: false, onLink: onLink
            )
        )
        let store = Storage(
            defaults: testDefaults,
            markerStore: InMemoryMarkerStore(),
            installMarkerStore: InMemoryMarkerStore()
        )
        WarpLink.storage = store
        return store
    }
}
