import XCTest
@testable import WarpLink

final class WarpLinkAutoWireTests: XCTestCase {

    private let apiKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    private let warpLinkURL = URL(string: "https://aplnk.to/abc123")!
    // A different slug on the same host: a new arrival, not a repeat.
    private let secondWarpLinkURL = URL(string: "https://aplnk.to/xyz789")!

    /// Records what the SDK sent and answers inline, so every call below
    /// finishes before it returns. No expectations, no timeouts, no sleeps.
    private var transport: InlineTransport!
    /// Flipped by a test before `configure()` to serve a no-match instead.
    private var attributionMatches = true

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        attributionMatches = true
        transport = InlineTransport.serving { [unowned self] path in
            if path.contains("attribution") {
                return attributionMatches ? Self.matchedAttributionJSON : ["matched": false]
            }
            if path.contains("resolve") { return Self.linkJSON }
            return ["valid": true, "domains": ["aplnk.to"]]
        }
        makeSDKSynchronous(transport)
    }

    override func tearDown() {
        // Restores the live transport and the main-queue hop.
        WarpLink.reset()
        transport = nil
        super.tearDown()
    }

    // MARK: - Cold / warm start → onLink

    // conformance: WL-S01
    func testOpenDispatchesColdStartToOnLink() {
        let box = Box<Result<WarpLinkDeepLink?, WarpLinkError>>()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeferredCheck: false,
            onLink: { result in box.value = result }
        ))

        XCTAssertTrue(WarpLink.open(warpLinkURL))

        guard case .success(let link?) = box.value else {
            return XCTFail("Expected a resolved link, got \(String(describing: box.value))")
        }
        XCTAssertFalse(link.isDeferred)
        XCTAssertEqual(link.linkId, "550e8400-e29b-41d4-a716-446655440000")
    }

    func testContinueForwardsUserActivityToOnLink() {
        let box = Box<Result<WarpLinkDeepLink?, WarpLinkError>>()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeferredCheck: false,
            onLink: { result in box.value = result }
        ))

        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = warpLinkURL
        XCTAssertTrue(WarpLink.continue(activity))

        guard case .success(let link?) = box.value else {
            return XCTFail("Expected a resolved link, got \(String(describing: box.value))")
        }
        XCTAssertEqual(link.linkId, "550e8400-e29b-41d4-a716-446655440000")
    }

    // conformance: WL-S26
    func testPasswordProtectedLinkReachesOnLinkAsPasswordRequired() {
        // Resolve refuses a password protected link with a 403 that carries no
        // destination and no platform URLs. The host has to be told which
        // refusal it was, so it can send the user to the short URL in a
        // browser instead of treating it as a dead link or a bad key.
        makeSDKSynchronous(Self.refusingWithPasswordRequired())

        let box = Box<Result<WarpLinkDeepLink?, WarpLinkError>>()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeferredCheck: false,
            onLink: { result in box.value = result }
        ))

        XCTAssertTrue(WarpLink.open(warpLinkURL))

        guard case .failure(let error) = box.value else {
            return XCTFail("Expected a failure, got \(String(describing: box.value))")
        }
        guard case .passwordRequired = error else {
            return XCTFail("Expected passwordRequired, got \(error)")
        }
    }

    /// Answers the resolve call with the API's password refusal and every other
    /// call with a normal 200, so only the branch under test changes.
    private static func refusingWithPasswordRequired() -> InlineTransport {
        InlineTransport { request in
            let path = request.url?.path ?? ""
            guard path.contains("resolve") else {
                let ok = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!
                let body = try? JSONSerialization.data(
                    withJSONObject: ["valid": true, "domains": ["aplnk.to"]]
                )
                return (body, ok, nil)
            }
            let refusal = HTTPURLResponse(
                url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil
            )!
            let body = try? JSONSerialization.data(withJSONObject: [
                "error": [
                    "code": "PASSWORD_REQUIRED",
                    "message": "This link is password protected.",
                ],
            ])
            return (body, refusal, nil)
        }
    }

    // conformance: WL-S09
    func testNonWarpLinkURLIsNotHandled() {
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeferredCheck: false,
            onLink: { _ in XCTFail("Should not dispatch for a non-WarpLink URL") }
        ))
        XCTAssertFalse(WarpLink.open(URL(string: "https://example.com/page")!))
    }

    // conformance: WL-S10
    func testMultiSegmentPathOnWarpLinkDomainIsNotHandled() {
        // The published AASA defaults to paths ["*"], so iOS hands the app every
        // URL on the domain. A slug can never contain "/", so the SDK must not
        // claim /blog/hello: returning true would swallow a URL it cannot
        // resolve instead of letting the host app's own router see it.
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeferredCheck: false,
            onLink: { _ in XCTFail("Should not dispatch for a multi-segment path") }
        ))
        XCTAssertFalse(WarpLink.open(URL(string: "https://aplnk.to/blog/hello")!))
    }

    // MARK: - Dedupe

    // conformance: WL-S03
    func testOpenDedupesRepeatedURL() {
        let counter = Counter()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeferredCheck: false,
            onLink: { _ in counter.increment() }
        ))

        XCTAssertTrue(WarpLink.open(warpLinkURL))
        XCTAssertTrue(WarpLink.open(warpLinkURL)) // duplicate within window → suppressed
        XCTAssertEqual(counter.value, 1, "Duplicate URL within the dedupe window must dispatch once")
    }

    // conformance: WL-S02
    func testSecondDifferentURLDispatchesAgain() {
        // The dedupe window suppresses a REPEAT of one arrival, not a new
        // navigation. A regression that keyed the window on the host alone, or
        // that suppressed for the app's lifetime, would swallow every link
        // after the first and look identical to a working SDK in the tests
        // above, which only ever send one URL twice.
        let counter = Counter()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeferredCheck: false,
            onLink: { _ in counter.increment() }
        ))

        XCTAssertTrue(WarpLink.open(warpLinkURL))
        XCTAssertTrue(WarpLink.open(secondWarpLinkURL))
        XCTAssertEqual(
            counter.value, 2,
            "A second, different URL is a new arrival and must dispatch its own event"
        )
    }

    // MARK: - Opt-out

    // conformance: WL-S19
    func testAutoHandlingOffStopsBothEntryPointsAndLeavesHandleDeepLinkWorking() {
        // Both automatic entry points must honour the flag, not just the one a
        // given host happens to wire. open(_:) carries a URL context and
        // continue(_:) carries a Universal Link activity, so a test that only
        // sends open() leaves the activity path free to dispatch. Android
        // shipped precisely that asymmetry: cold start honoured the flag and
        // the warm-start entry point did not.
        let dispatches = Counter()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeepLinkHandling: false,
            autoDeferredCheck: false,
            onLink: { _ in dispatches.increment() }
        ))

        XCTAssertFalse(WarpLink.open(warpLinkURL))

        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = secondWarpLinkURL
        XCTAssertFalse(WarpLink.continue(activity))

        XCTAssertEqual(
            dispatches.value, 0,
            "With auto handling off, no automatic entry point may reach onLink"
        )

        // Opting out turns off the automatic ROUTING, not the SDK. The host
        // took the links back, so its own call must still resolve one:
        // disabling handleDeepLink along with the flag would leave an opted-out
        // app with no way to read a link at all.
        let resolved = Box<Result<WarpLinkDeepLink, WarpLinkError>>()
        WarpLink.handleDeepLink(warpLinkURL) { result in resolved.value = result }

        guard case .success(let link)? = resolved.value else {
            return XCTFail(
                "handleDeepLink must still resolve while auto handling is off, "
                + "got \(String(describing: resolved.value))"
            )
        }
        XCTAssertEqual(link.linkId, "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(
            dispatches.value, 0,
            "handleDeepLink answers its own completion and must not also reach onLink"
        )
    }

    // MARK: - Deferred → onLink

    func testAutoDeferredCheckDispatchesDeferredMatchToOnLink() {
        let box = Box<Result<WarpLinkDeepLink?, WarpLinkError>>()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeepLinkHandling: false,
            autoDeferredCheck: false,
            onLink: { result in box.value = result }
        ))
        WarpLink.storage = freshStorage()

        WarpLink.runAutoDeferredCheck()

        guard case .success(let link?) = box.value else {
            return XCTFail("Expected a deferred link, got \(String(describing: box.value))")
        }
        XCTAssertTrue(link.isDeferred)
        XCTAssertEqual(link.linkId, "link-deferred-1")
        XCTAssertEqual(link.customParams["promo"]?.stringValue, "welcome")
    }

    // conformance: WL-S05
    func testAutoDeferredCheckDoesNotDispatchNoMatchToOnLink() {
        attributionMatches = false
        let dispatches = Counter()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeepLinkHandling: false,
            autoDeferredCheck: false,
            onLink: { _ in dispatches.increment() }
        ))
        let store = freshStorage()
        WarpLink.storage = store

        WarpLink.runAutoDeferredCheck()

        // The response is already applied: the check ran to completion inside
        // the call above, so the gate is closed and nothing is still in flight.
        XCTAssertTrue(store.isAttributionComplete)
        XCTAssertEqual(
            dispatches.value, 0,
            "A deferred no-match must not dispatch to onLink (uniform with Android/RN)"
        )
    }

    func testAutoDeferredCheckStillAttributesWithoutOnLinkSink() {
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeepLinkHandling: false,
            autoDeferredCheck: false
        ))
        WarpLink.storage = freshStorage()

        WarpLink.runAutoDeferredCheck()

        // A bare configure(apiKey:) carries no onLink but is documented to
        // attribute the install automatically, so the match must still run and
        // be recorded server-side even with nowhere to route the deep link.
        XCTAssertEqual(
            transport.requestCount(forPathContaining: "attribution"), 1,
            "A sinkless auto check must still attribute the install"
        )
    }

    // conformance: WL-S14
    func testDefaultConfigureFiresTheDeferredCheck() {
        // Configure with auto off first so the storage that the opt-out path
        // will use can be cleared of any state left by an earlier run.
        WarpLink.configure(apiKey: apiKey, options: TestSupport.noAuto)
        WarpLink.storage?.clearAll()
        XCTAssertEqual(
            transport.requestCount(forPathContaining: "attribution"), 0,
            "autoDeferredCheck: false must not attribute"
        )

        // Default options are opt-out: configure() itself runs the check.
        WarpLink.configure(apiKey: apiKey)
        WarpLink.storage?.clearAll()

        XCTAssertEqual(
            transport.requestCount(forPathContaining: "attribution"), 1,
            "configure() with default options must fire the deferred check"
        )
    }

    func testAutoDeferredCheckSkipsWhenAlreadyComplete() {
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeepLinkHandling: false,
            autoDeferredCheck: false,
            onLink: { _ in XCTFail("Should not re-dispatch once attribution is complete") }
        ))
        let store = freshStorage()
        store.markAttributionComplete()
        // Seed a real cached match. Without it, deleting the completion guard
        // still passed, because there was nothing to re-fire.
        store.cachedAttribution = WarpLinkDeepLink(
            linkId: "lnk_1", destination: "https://example.com", isDeferred: true
        )
        WarpLink.storage = store

        WarpLink.runAutoDeferredCheck()
    }

    // MARK: - Helpers

    private func freshStorage() -> Storage {
        let defaults = UserDefaults(suiteName: "WarpLinkAutoWireTests")!
        defaults.removePersistentDomain(forName: "WarpLinkAutoWireTests")
        return Storage(
            defaults: defaults,
            markerStore: InMemoryMarkerStore(),
            installMarkerStore: InMemoryMarkerStore()
        )
    }

    private static let linkJSON: [String: Any] = [
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "slug": "abc123",
        "domain": "aplnk.to",
        "destination_url": "https://example.com",
        "ios_url": "myapp://page",
        "ios_fallback_url": NSNull(),
        "custom_params": ["promo": "summer"],
        "created_at": "2026-01-01T00:00:00.000Z",
    ]

    private static let matchedAttributionJSON: [String: Any] = [
        "matched": true,
        "match_type": "probabilistic",
        "match_confidence": 0.75,
        "link_id": "link-deferred-1",
        "deep_link_url": "myapp://deferred",
        "destination_url": "https://example.com/deferred",
        "custom_params": ["promo": "welcome"],
        "install_id": "inst-1",
    ]
}
