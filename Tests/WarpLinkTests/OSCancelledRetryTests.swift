import XCTest
@_spi(ReactNative) @testable import WarpLink

/// A connection that died while the app was suspended reports the same
/// `URLError(.cancelled)` a supersede or a reconfigure causes on purpose, and
/// `RetryPolicy` used to refuse to retry any of them. That conflated two
/// different facts: "this attempt was abandoned on purpose" and "the OS gave up
/// on a still-wanted attempt's connection". A tap on a physical iPhone that had
/// been backgrounded about 57s reused a dead connection, failed in 12ms with
/// `URLError(.cancelled)`, and was never retried: the user had to tap again.
/// Measured on iPhone 17 Pro, iOS 26.6.2, TestFlight build 1.1.0 (1). Bead:
/// warplink-i7oa.
///
/// These tests reproduce the OS-cancelled failure directly from the transport,
/// never through this SDK's own `.cancel()`, which is what makes them prove the
/// still-current case: `CancellingTransport`'s held requests are how the
/// existing suite proves the ABANDONED case already behaves correctly, and nothing
/// here duplicates that, it only adds the currency split the bug was missing.
final class OSCancelledRetryTests: XCTestCase {

    private let apiKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    private let tapped = URL(string: "https://aplnk.to/abc123")!
    private let other = URL(string: "https://aplnk.to/second")!
    private var recorder: ScheduleRecorder!

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        recorder = ScheduleRecorder()
    }

    override func tearDown() {
        WarpLink.reset()
        recorder = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private static func validated(_ request: URLRequest) -> (Data?, URLResponse?, Error?) {
        let ok = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        let body = try? JSONSerialization.data(
            withJSONObject: ["valid": true, "domains": ["aplnk.to"]]
        )
        return (body, ok, nil)
    }

    private static func ok(_ request: URLRequest) -> (Data?, URLResponse?, Error?) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        return (
            try? JSONSerialization.data(withJSONObject: BoundedResolveRetryTests.linkJSON), response, nil
        )
    }

    /// Answers `/sdk/validate` and `/attribution/match` with 200s, and scripts
    /// the resolve responses. The first attempt fails the way the OS reports a
    /// connection that died in the background, `(nil, nil, URLError(.cancelled))`,
    /// never through this SDK's own `.cancel()`.
    private func transport(resolveScript: [(Data?, URLResponse?, Error?)]) -> InlineTransport {
        var remaining = resolveScript
        return InlineTransport { request in
            guard request.url?.path.contains("/links/resolve/") == true else {
                return Self.validated(request)
            }
            return remaining.isEmpty ? Self.ok(request) : remaining.removeFirst()
        }
    }

    private func configure(
        _ transport: InlineTransport,
        onLink: @escaping @Sendable (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        makeSDKSynchronous(transport)
        recorder.install()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeferredCheck: false, onLink: onLink
        ))
    }

    private func tapIds(_ log: SentRequestLog) -> [String?] {
        log.tapIds(forPathContaining: "/links/resolve/")
    }

    // MARK: - A current automatic tap retries

    // conformance: WL-S27
    func testACurrentTapRetriesAnOSCancelledAttemptAndDeliversOnce() {
        let t = transport(resolveScript: [(nil, nil, URLError(.cancelled))])

        let results = Results()
        configure(t) { results.append($0) }
        XCTAssertTrue(WarpLink.open(tapped))

        XCTAssertEqual(
            t.requestCount(forPathContaining: "/links/resolve/"), 2,
            "an OS-cancelled attempt on a still-current tap must be retried"
        )
        XCTAssertEqual(results.all.count, 1, "one tap, one delivery")
        guard case .success(let link?)? = results.all.first else {
            return XCTFail("expected the retry's link, got \(String(describing: results.all.first))")
        }
        XCTAssertEqual(link.linkId, "550e8400-e29b-41d4-a716-446655440000")

        // WL-S27's tap id rule: the retry a cancellation buys is still one tap.
        let ids = tapIds(t.log)
        XCTAssertEqual(ids.count, 2)
        XCTAssertNotNil(ids.first ?? nil)
        XCTAssertEqual(Set(ids.compactMap { $0 }).count, 1, "both attempts must carry the same tap id")
    }

    // MARK: - A superseded tap stays unretried

    func testASupersededTapDoesNotRetryAfterAnOSCancelledAttempt() {
        // Tap A is held open on the wire. Tap B supersedes it, which cancels A
        // through this SDK's own `.cancel()` and answers A's completion with
        // URLError(.cancelled), exactly as the OS does for a dead connection. A
        // was abandoned, not failed on a live tap, and must not retry.
        let t = CancellingTransport(holdingPathContaining: "/links/resolve/")
        SDKEnvironment.makeTransport = { t }
        SDKEnvironment.deliver = { work in work() }
        SDKEnvironment.schedule = { _, work in work() }

        let results = Results()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeferredCheck: false, onLink: { results.append($0) }
        ))

        XCTAssertTrue(WarpLink.open(tapped))
        XCTAssertEqual(t.held.count, 1, "tap A is on the wire")
        XCTAssertTrue(WarpLink.open(other))

        // Exactly one held request per tap: neither A nor B retried.
        XCTAssertEqual(
            t.held.count, 2,
            "A must not have retried after being cancelled by the supersede"
        )
        XCTAssertTrue(t.held[0].cancelled, "tap A's request must be stopped")
        XCTAssertEqual(results.all.count, 0, "neither tap has answered yet")
    }

    // MARK: - A manual handleDeepLink caller retries too

    func testAManualHandleDeepLinkRetriesAnOSCancelledAttempt() {
        let t = transport(resolveScript: [(nil, nil, URLError(.cancelled))])
        configure(t) { _ in XCTFail("handleDeepLink answers its own completion") }

        var answers: [Result<WarpLinkDeepLink, WarpLinkError>] = []
        WarpLink.handleDeepLink(tapped) { answers.append($0) }

        XCTAssertEqual(answers.count, 1)
        guard case .success(let link)? = answers.first else {
            return XCTFail("expected a resolved link, got \(String(describing: answers.first))")
        }
        XCTAssertEqual(link.linkId, "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(
            t.requestCount(forPathContaining: "/links/resolve/"), 2,
            "a manual caller is never superseded, but it must still retry a live cancellation"
        )
    }

    // MARK: - The React Native bridge

    // conformance: WL-S27
    func testACurrentBridgeResolveRetriesAnOSCancelledAttempt() {
        let t = transport(resolveScript: [(nil, nil, URLError(.cancelled))])
        SDKEnvironment.makeTransport = { t }
        SDKEnvironment.deliver = { work in work() }
        SDKEnvironment.schedule = { _, work in work() }
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(autoDeferredCheck: false))

        var answer: Result<WarpLinkDeepLink, WarpLinkError>?
        WarpLink.resolveFromReactNativeBridge(tapped) { answer = $0 }

        guard case .success(let link) = answer else {
            return XCTFail("expected the retry to resolve, got \(String(describing: answer))")
        }
        XCTAssertEqual(link.linkId, "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(t.requestCount(forPathContaining: "/links/resolve/"), 2)
    }

    func testASupersededBridgeResolveDoesNotRetryAfterAnOSCancelledAttempt() {
        let t = CancellingTransport(holdingPathContaining: "/links/resolve/")
        SDKEnvironment.makeTransport = { t }
        SDKEnvironment.deliver = { work in work() }
        SDKEnvironment.schedule = { _, work in work() }
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(autoDeferredCheck: false))

        var firstAnswer: Result<WarpLinkDeepLink, WarpLinkError>?
        WarpLink.resolveFromReactNativeBridge(tapped) { firstAnswer = $0 }
        XCTAssertEqual(t.held.count, 1)

        var secondAnswer: Result<WarpLinkDeepLink, WarpLinkError>?
        WarpLink.resolveFromReactNativeBridge(other) { secondAnswer = $0 }

        // Superseded: settles once with the cancellation, and never retries.
        guard case .failure(.networkError(let underlying)) = firstAnswer else {
            return XCTFail("expected the superseded call to settle, got \(String(describing: firstAnswer))")
        }
        XCTAssertEqual((underlying as? URLError)?.code, .cancelled)
        XCTAssertEqual(t.held.count, 2, "no retry from the superseded call")
        XCTAssertNil(secondAnswer, "the newer resolve is still on the wire")
    }

    // MARK: - The deferred check

    func testACurrentDeferredCheckRetriesAnOSCancelledAttempt() {
        var remaining = 1
        let scripted = InlineTransport { request in
            guard request.url?.path.contains("/attribution/match") == true else {
                return Self.validated(request)
            }
            if remaining > 0 {
                remaining -= 1
                return (nil, nil, URLError(.cancelled))
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (try? JSONSerialization.data(withJSONObject: ["matched": false]), response, nil)
        }
        makeSDKSynchronous(scripted)
        recorder.install()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(autoDeferredCheck: false))
        WarpLink.storage = freshStorage()

        let results = Results()
        WarpLink.checkDeferredDeepLink { results.append($0) }

        XCTAssertEqual(
            scripted.requestCount(forPathContaining: "/attribution/match"), 2,
            "an OS-cancelled attempt on a still-current check must be retried"
        )
        XCTAssertEqual(results.all.count, 1, "one check, one answer")
        guard case .success(let link)? = results.all.first else {
            return XCTFail("expected the retry's no-match, got \(String(describing: results.all.first))")
        }
        XCTAssertNil(link)
    }

    /// A storage nothing outside this test can see.
    private func freshStorage() -> Storage {
        let defaults = UserDefaults(suiteName: "OSCancelledRetryTests")!
        defaults.removePersistentDomain(forName: "OSCancelledRetryTests")
        return Storage(
            defaults: defaults,
            markerStore: InMemoryMarkerStore(),
            installMarkerStore: InMemoryMarkerStore()
        )
    }
}
