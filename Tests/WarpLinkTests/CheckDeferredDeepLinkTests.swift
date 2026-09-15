import XCTest
@testable import WarpLink

private class DeferredMockProtocol: URLProtocol {
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

final class CheckDeferredDeepLinkTests: XCTestCase {

    private let testApiKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        testDefaults = UserDefaults(suiteName: "CheckDeferredDeepLinkTests")!
        testDefaults.removePersistentDomain(forName: "CheckDeferredDeepLinkTests")
        URLProtocol.registerClass(DeferredMockProtocol.self)
        // The bounded retry now sits under every failed attribution attempt and
        // its backoff is real time, so an offline test here would spend about
        // 1.65 s sleeping inside a 2 s expectation and flake on a loaded
        // machine. The waits run inline instead; the request count, which is
        // what these tests are about, is unchanged. Undone by `reset()`.
        SDKEnvironment.schedule = { _, work in work() }
    }

    override func tearDown() {
        URLProtocol.unregisterClass(DeferredMockProtocol.self)
        DeferredMockProtocol.requestHandler = nil
        testDefaults.removePersistentDomain(forName: "CheckDeferredDeepLinkTests")
        WarpLink.reset()
        super.tearDown()
    }

    // MARK: - Tests

    func testNotConfiguredReturnsError() {
        let exp = expectation(description: "completion")
        WarpLink.checkDeferredDeepLink { result in
            if case .failure(let error) = result, case .notConfigured = error {
                // Expected
            } else {
                XCTFail("Expected notConfigured, got \(result)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testFirstLaunchSuccessfulMatch() {
        configureWithMockStorage()
        mockAttributionResponse(matched: true)

        let exp = expectation(description: "completion")
        WarpLink.checkDeferredDeepLink { result in
            guard case .success(let deepLink) = result, let deepLink = deepLink else {
                XCTFail("Expected matched deep link, got \(result)")
                exp.fulfill()
                return
            }
            XCTAssertTrue(deepLink.isDeferred)
            XCTAssertEqual(deepLink.linkId, "link-abc-123")
            XCTAssertEqual(deepLink.destination, "https://example.com/42")
            XCTAssertEqual(deepLink.deepLinkUrl, "myapp://content/42")
            XCTAssertEqual(deepLink.matchType, .probabilistic)
            XCTAssertEqual(deepLink.matchConfidence, 0.85)
            XCTAssertEqual(deepLink.customParams["promo"]?.stringValue, "summer")
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
        XCTAssertTrue(WarpLink.storage?.isAttributionComplete ?? false)
    }

    func testFirstLaunchNoMatch() {
        configureWithMockStorage()
        mockAttributionResponse(matched: false)

        let exp = expectation(description: "completion")
        WarpLink.checkDeferredDeepLink { result in
            guard case .success(let deepLink) = result else {
                XCTFail("Expected success, got \(result)")
                exp.fulfill()
                return
            }
            XCTAssertNil(deepLink)
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    // conformance: WL-S21
    func testFirstLaunchNetworkError() {
        configureWithMockStorage()
        DeferredMockProtocol.requestHandler = { _ in
            throw NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorNotConnectedToInternet
            )
        }

        // Captured as a bare `Error`, so the assertions below interrogate the
        // value the host is handed rather than restating the `Result` signature
        // the compiler already pins. If that signature is ever widened to
        // `Error`, this is what stops a raw platform error leaking through it.
        let failure = Box<Error>()
        let exp = expectation(description: "completion")
        WarpLink.checkDeferredDeepLink { result in
            if case .failure(let error) = result { failure.value = error }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)

        // URLSession raised this one below the SDK, so it is the SDK's job to
        // hand it over as its own type. A host switches over WarpLinkError to
        // decide what to do; an NSError it cannot exhaust, and a case picked at
        // random tells it the wrong thing.
        guard let warpLinkError = failure.value as? WarpLinkError else {
            return XCTFail(
                "A transport failure must reach the host as a WarpLinkError, "
                + "got \(String(describing: failure.value))"
            )
        }
        guard case .networkError(let cause) = warpLinkError else {
            return XCTFail("Expected .networkError, got \(warpLinkError)")
        }
        // Wrapped, not replaced: the platform error survives inside the case,
        // so a host (or a crash report) can still name the actual fault.
        XCTAssertEqual((cause as NSError).domain, NSURLErrorDomain)
        XCTAssertEqual((cause as NSError).code, NSURLErrorNotConnectedToInternet)

        // A failed attempt marks "attempted" but NOT "complete", so it retries.
        XCTAssertTrue(WarpLink.storage?.hasAttemptedAttribution ?? false)
        XCTAssertFalse(WarpLink.storage?.isAttributionComplete ?? true)
    }

    // conformance: WL-S06
    func testFailedAttemptRetriesOnNextLaunch() {
        configureWithMockStorage()

        // Launch 1: offline → failure, not complete.
        DeferredMockProtocol.requestHandler = { _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        }
        let firstExp = expectation(description: "first attempt")
        WarpLink.checkDeferredDeepLink { result in
            if case .failure = result {} else { XCTFail("Expected failure, got \(result)") }
            firstExp.fulfill()
        }
        waitForExpectations(timeout: 2)
        XCTAssertFalse(WarpLink.storage?.isAttributionComplete ?? true)

        // Launch 2: back online → the SDK retries and completes with a match.
        mockAttributionResponse(matched: true)
        let secondExp = expectation(description: "retry")
        WarpLink.checkDeferredDeepLink { result in
            guard case .success(let deepLink) = result, let deepLink = deepLink else {
                XCTFail("Expected matched deep link on retry, got \(result)")
                secondExp.fulfill()
                return
            }
            XCTAssertTrue(deepLink.isDeferred)
            XCTAssertEqual(deepLink.linkId, "link-abc-123")
            secondExp.fulfill()
        }
        waitForExpectations(timeout: 2)
        XCTAssertTrue(WarpLink.storage?.isAttributionComplete ?? false)
    }

    // conformance: WL-S04
    func testSecondLaunchReturnsCachedMatch() {
        configureWithMockStorage()
        mockAttributionResponse(matched: true)

        // First call — triggers API and caches
        let firstExp = expectation(description: "first call")
        WarpLink.checkDeferredDeepLink { _ in firstExp.fulfill() }
        waitForExpectations(timeout: 2)

        // Track whether a network request is made on second call
        var networkRequestMade = false
        DeferredMockProtocol.requestHandler = { request in
            // Only count attribution match requests, not validation
            if request.url?.path.contains("attribution") == true {
                networkRequestMade = true
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: ["matched": false])
            return (response, data)
        }

        // Second call — should use cache
        let secondExp = expectation(description: "second call")
        WarpLink.checkDeferredDeepLink { result in
            guard case .success(let deepLink) = result, let deepLink = deepLink else {
                XCTFail("Expected cached deep link, got \(result)")
                secondExp.fulfill()
                return
            }
            XCTAssertTrue(deepLink.isDeferred)
            XCTAssertEqual(deepLink.linkId, "link-abc-123")
            secondExp.fulfill()
        }
        waitForExpectations(timeout: 2)
        XCTAssertFalse(networkRequestMade, "Should not make network request on second launch")
    }

    // MARK: - Reinstall reporting (is_reinstall)

    // conformance: WL-S24
    func testFirstInstallReportsNotAReinstall() {
        configureWithMockStorage()
        let reported = ReportedFlags()
        recordingAttributionResponse(reported)

        let exp = expectation(description: "completion")
        WarpLink.checkDeferredDeepLink { _ in exp.fulfill() }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(
            reported.all, [false],
            "a device with no prior attribution must report a first install, explicitly"
        )
    }

    // conformance: WL-S16
    // Also WL-S24. This is the true half of the wire flag, where the WL-S24
    // test above covers the false half. The checker collects markers per test
    // tree, not per test, so the second id enforces nothing extra; it is here
    // so a reader can see both contracts this test serves.
    func testReinstallReportsAReinstall() {
        // The device completed attribution under an earlier install: the
        // Keychain marker outlived the app delete, the gate did not.
        let deviceMarker = InMemoryMarkerStore()
        deviceMarker.mark("warplink_attribution_complete")
        let store = configureWithMockStorage(markerStore: deviceMarker)
        let reported = ReportedFlags()
        recordingAttributionResponse(reported)

        let exp = expectation(description: "completion")
        WarpLink.checkDeferredDeepLink { result in
            guard case .success(let deepLink) = result, deepLink != nil else {
                XCTFail("A reinstall must be attributed again, got \(result)")
                exp.fulfill()
                return
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(reported.all, [true], "a reinstall must be tagged on the wire")
        XCTAssertTrue(store.isAttributionComplete, "and must close the gate for the new install")
    }

    func testSecondLaunchWithinOneInstallDoesNotReAttribute() {
        let deviceMarker = InMemoryMarkerStore()
        let installMarker = InMemoryMarkerStore()
        configureWithMockStorage(markerStore: deviceMarker, installMarkerStore: installMarker)
        let reported = ReportedFlags()
        recordingAttributionResponse(reported)

        let firstExp = expectation(description: "first launch")
        WarpLink.checkDeferredDeepLink { _ in firstExp.fulfill() }
        waitForExpectations(timeout: 2)

        // Relaunch: a fresh Storage over the same install and the same device,
        // which is what the SDK builds on every cold start.
        WarpLink.storage = Storage(
            defaults: testDefaults,
            markerStore: deviceMarker,
            installMarkerStore: installMarker
        )

        let secondExp = expectation(description: "second launch")
        WarpLink.checkDeferredDeepLink { result in
            guard case .success(let deepLink) = result, deepLink?.linkId == "link-abc-123" else {
                XCTFail("Expected the cached match, got \(result)")
                secondExp.fulfill()
                return
            }
            secondExp.fulfill()
        }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(
            reported.all, [false],
            "the second launch of one install must not attribute again, as a reinstall or at all"
        )
    }

    func testSecondLaunchReturnsNilWhenNoMatch() {
        configureWithMockStorage()
        mockAttributionResponse(matched: false)

        // First call — no match, no cache
        let firstExp = expectation(description: "first call")
        WarpLink.checkDeferredDeepLink { _ in firstExp.fulfill() }
        waitForExpectations(timeout: 2)

        // Second call — should return nil without API call
        var networkRequestMade = false
        DeferredMockProtocol.requestHandler = { request in
            if request.url?.path.contains("attribution") == true {
                networkRequestMade = true
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: ["matched": false])
            return (response, data)
        }

        let secondExp = expectation(description: "second call")
        WarpLink.checkDeferredDeepLink { result in
            guard case .success(let deepLink) = result else {
                XCTFail("Expected success, got \(result)")
                secondExp.fulfill()
                return
            }
            XCTAssertNil(deepLink)
            secondExp.fulfill()
        }
        waitForExpectations(timeout: 2)
        XCTAssertFalse(networkRequestMade, "Should not make network request on second launch")
    }

    func testConcurrentCallersShareTheInFlightResult() {
        configureWithMockStorage()
        let attributionRequests = Counter()
        countedAttributionResponse(attributionRequests)

        let firstLinkId = Box<String>()
        let secondLinkId = Box<String>()
        let firstExp = expectation(description: "first caller")
        let secondExp = expectation(description: "second caller")

        WarpLink.checkDeferredDeepLink { result in
            if case .success(let deepLink) = result { firstLinkId.value = deepLink?.linkId }
            firstExp.fulfill()
        }
        // The first call claims the check synchronously, so this caller is
        // parked on it rather than answered from the (still empty) cache.
        WarpLink.checkDeferredDeepLink { result in
            if case .success(let deepLink) = result { secondLinkId.value = deepLink?.linkId }
            secondExp.fulfill()
        }

        waitForExpectations(timeout: 2)
        XCTAssertEqual(firstLinkId.value, "link-abc-123")
        XCTAssertEqual(
            secondLinkId.value, "link-abc-123",
            "A parked caller must receive the in-flight result, not a nil cache"
        )
        XCTAssertEqual(attributionRequests.value, 1, "Concurrent callers must share one match request")
    }

    // conformance: WL-S07
    func testCheckAbandonedByReconfigureDoesNotAnswerTheSuccessorsCallers() {
        configureWithMockStorage()
        let abandonedGate = DispatchSemaphore(value: 0)
        let successorGate = DispatchSemaphore(value: 0)
        gatedAttributionResponses(abandoned: abandonedGate, successor: successorGate)

        // Claims the in-flight slot; its match request is held open.
        let abandonedResult = Box<Result<WarpLinkDeepLink?, WarpLinkError>>()
        let abandonedExp = expectation(description: "abandoned caller")
        WarpLink.checkDeferredDeepLink { result in
            abandonedResult.value = result
            abandonedExp.fulfill()
        }

        // Reconfiguring abandons that check. The replacement talks to a second
        // endpoint so the mock can tell the two match requests apart.
        WarpLink.configure(apiKey: testApiKey, options: WarpLinkOptions(
            apiEndpoint: Self.successorEndpoint,
            autoDeepLinkHandling: false,
            autoDeferredCheck: false
        ))
        WarpLink.storage = Storage(
            defaults: testDefaults,
            markerStore: InMemoryMarkerStore(),
            installMarkerStore: InMemoryMarkerStore()
        )

        let successorExp = expectation(description: "successor caller")
        WarpLink.checkDeferredDeepLink { _ in successorExp.fulfill() }

        // Parked on the replacement check, so it must never be answered by the
        // abandoned one, which finishes first and reports a no-match.
        let parkedResult = Box<Result<WarpLinkDeepLink?, WarpLinkError>>()
        let parkedCalls = Counter()
        let parkedExp = expectation(description: "parked caller")
        WarpLink.checkDeferredDeepLink { result in
            parkedResult.value = result
            parkedCalls.increment()
            parkedExp.fulfill()
        }

        abandonedGate.signal()
        wait(for: [abandonedExp], timeout: 2)
        successorGate.signal()
        wait(for: [successorExp, parkedExp], timeout: 2)

        guard case .success(let deepLink?) = parkedResult.value else {
            return XCTFail(
                "A caller parked on the replacement check must receive its match, "
                + "got \(String(describing: parkedResult.value))"
            )
        }
        XCTAssertEqual(deepLink.linkId, "link-abc-123")
        XCTAssertEqual(parkedCalls.value, 1, "A parked caller must be answered once")

        // The abandoned check's response is discarded rather than applied: it
        // would otherwise blank the replacement's cached attribution, since both
        // storages persist to the same defaults. Its caller is answered with the
        // no-op success, not a fabricated `.notConfigured` for a configured SDK.
        guard case .success(let abandonedLink)? = abandonedResult.value,
              abandonedLink == nil else {
            return XCTFail(
                "An abandoned check must answer with the no-op success, "
                + "got \(String(describing: abandonedResult.value))"
            )
        }
    }

    func testReconfigureDuringAutoCheckDeliversNoErrorToOnLink() {
        // Reconfiguring is benign and normal (a second configure() from a scene
        // delegate, an API key rotation, an environment switch). The auto check
        // it abandons must stay silent: the SDK IS configured, so pushing a
        // "not configured" failure into onLink would be a misleading error the
        // host may show to users.
        let gate = DispatchSemaphore(value: 0)
        let inFlight = expectation(description: "match request in flight")
        inFlight.assertForOverFulfill = false
        gatedNoMatchResponse(gate: gate, reached: inFlight)

        // The claim is a negative: nothing reaches onLink. It is written as an
        // inverted expectation rather than a sleep, and the difference is the
        // whole point. An inverted expectation that runs out of time PASSES,
        // whereas the sleep it replaces FAILED whenever a loaded machine starved
        // the main queue past its margin. That starvation is what made this
        // suite flake under a parallel build, not anything about the SDK.
        let silence = expectation(description: "onLink must stay silent")
        silence.isInverted = true
        let options = WarpLinkOptions(
            autoDeepLinkHandling: false,
            autoDeferredCheck: false,
            onLink: { result in if case .failure = result { silence.fulfill() } }
        )
        WarpLink.configure(apiKey: testApiKey, options: options)
        let store = Storage(
            defaults: testDefaults,
            markerStore: InMemoryMarkerStore(),
            installMarkerStore: InMemoryMarkerStore()
        )
        WarpLink.storage = store

        WarpLink.runAutoDeferredCheck()
        wait(for: [inFlight], timeout: 2)

        WarpLink.configure(apiKey: testApiKey, options: options)
        WarpLink.storage = store
        gate.signal()
        wait(for: [silence], timeout: 0.6)

        XCTAssertFalse(
            store.isAttributionComplete,
            "An abandoned check must apply nothing to storage"
        )
    }

    // MARK: - Helpers

    private static let successorEndpoint = "https://successor.warplink.test/v1"

    /// Holds the attribution match request open until `gate` is signalled,
    /// fulfilling `reached` once the request is in flight, then answers no-match.
    private func gatedNoMatchResponse(gate: DispatchSemaphore, reached: XCTestExpectation) {
        DeferredMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            guard request.url?.path.contains("attribution") == true else {
                let valid: [String: Any] = ["valid": true, "domains": ["aplnk.to"]]
                return (response, try JSONSerialization.data(withJSONObject: valid))
            }
            reached.fulfill()
            _ = gate.wait(timeout: .now() + 5)
            return (response, try JSONSerialization.data(withJSONObject: ["matched": false]))
        }
    }

    @discardableResult
    private func configureWithMockStorage(
        markerStore: InMemoryMarkerStore = InMemoryMarkerStore(),
        installMarkerStore: InMemoryMarkerStore = InMemoryMarkerStore()
    ) -> Storage {
        // First configure with auto behavior off (avoids an early auto deferred
        // check before we inject deterministic storage).
        DeferredMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        WarpLink.configure(apiKey: testApiKey, options: TestSupport.noAuto)

        // Replace storage with ephemeral UserDefaults + in-memory marker stores
        // so tests touch neither the real Keychain nor the app container.
        let store = Storage(
            defaults: testDefaults,
            markerStore: markerStore,
            installMarkerStore: installMarkerStore
        )
        WarpLink.storage = store
        return store
    }

    /// Records the `is_reinstall` value of every attribution request served.
    private func recordingAttributionResponse(_ reported: ReportedFlags) {
        mockAttributionResponse(matched: true)
        guard let base = DeferredMockProtocol.requestHandler else {
            return XCTFail("Expected a mocked attribution handler")
        }
        DeferredMockProtocol.requestHandler = { request in
            if request.url?.path.contains("attribution") == true {
                let body = (try? JSONSerialization.jsonObject(
                    with: request.resolvedHTTPBody ?? Data()
                )) as? [String: Any]
                reported.append(body?["is_reinstall"] as? Bool)
            }
            return try base(request)
        }
    }

    /// A matched attribution response that counts the match requests it serves.
    private func countedAttributionResponse(_ requests: Counter) {
        mockAttributionResponse(matched: true)
        guard let base = DeferredMockProtocol.requestHandler else {
            return XCTFail("Expected a mocked attribution handler")
        }
        DeferredMockProtocol.requestHandler = { request in
            if request.url?.path.contains("attribution") == true { requests.increment() }
            return try base(request)
        }
    }

    private func mockAttributionResponse(matched: Bool) {
        DeferredMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let json = matched ? Self.matchedAttributionJSON : ["matched": false]
            let data = try JSONSerialization.data(withJSONObject: json)
            return (response, data)
        }
    }

    /// Holds every attribution match request open until its gate is signalled,
    /// so a test can interleave work with an in-flight check. The abandoned
    /// check keeps the original endpoint and the replacement uses
    /// `successorEndpoint`, so the two are told apart by host.
    private func gatedAttributionResponses(
        abandoned: DispatchSemaphore,
        successor: DispatchSemaphore
    ) {
        let successorHost = URL(string: Self.successorEndpoint)!.host
        DeferredMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            guard request.url?.path.contains("attribution") == true else {
                let valid: [String: Any] = ["valid": true, "domains": ["aplnk.to"]]
                return (response, try JSONSerialization.data(withJSONObject: valid))
            }
            let isSuccessor = request.url?.host == successorHost
            _ = (isSuccessor ? successor : abandoned).wait(timeout: .now() + 5)
            let json = isSuccessor ? Self.matchedAttributionJSON : ["matched": false]
            return (response, try JSONSerialization.data(withJSONObject: json))
        }
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
}
