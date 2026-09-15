import XCTest
@testable import WarpLink

/// A tap on a weak connection still delivers, and one tap bills one click.
final class BoundedResolveRetryTests: XCTestCase {

    private let apiKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    private let tapped = URL(string: "https://aplnk.to/abc123")!
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

    /// Answers `/sdk/validate` with a 200 and scripts the resolve responses.
    /// `InlineTransport`'s raw initializer calls its closure once per request,
    /// so "fail, fail, succeed" needs no new harness. Only `serving(_:)` and
    /// `failing(with:)` are fixed-response.
    private func transport(resolveScript: [(Data?, URLResponse?, Error?)]) -> InlineTransport {
        var remaining = resolveScript
        return InlineTransport { request in
            guard request.url?.path.contains("/links/resolve/") == true else {
                return Self.validated(request)
            }
            return remaining.isEmpty ? Self.ok(request) : remaining.removeFirst()
        }
    }

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
        return (try? JSONSerialization.data(withJSONObject: linkJSON), response, nil)
    }

    private static func status(
        _ code: Int, body: [String: Any] = [:]
    ) -> (URLRequest) -> (Data?, URLResponse?, Error?) {
        { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil
            )!
            return (try? JSONSerialization.data(withJSONObject: body), response, nil)
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

    /// The tap id each resolve request carried, in order.
    private func tapIds(_ log: SentRequestLog) -> [String?] {
        log.tapIds(forPathContaining: "/links/resolve/")
    }

    // MARK: - Retrying

    // conformance: WL-S21
    // conformance: WL-S27
    func testATransientFailureThenASuccessDeliversOneLink() {
        let dropped = URLError(.networkConnectionLost)
        let t = transport(resolveScript: [(nil, nil, dropped), (nil, nil, dropped)])

        let results = Results()
        configure(t) { results.append($0) }
        XCTAssertTrue(WarpLink.open(tapped))

        XCTAssertEqual(t.requestCount(forPathContaining: "/links/resolve/"), 3)
        XCTAssertEqual(results.all.count, 1, "one tap, one delivery")
        guard case .success(let link?)? = results.all.first else {
            return XCTFail("expected a resolved link, got \(String(describing: results.all.first))")
        }
        XCTAssertEqual(link.linkId, "550e8400-e29b-41d4-a716-446655440000")
    }

    // conformance: WL-S27
    func testEveryAttemptOfOneTapCarriesTheSameTapId() {
        let dropped = URLError(.networkConnectionLost)
        let t = transport(resolveScript: [(nil, nil, dropped), (nil, nil, dropped)])
        configure(t) { _ in }
        XCTAssertTrue(WarpLink.open(tapped))

        let ids = tapIds(t.log)
        XCTAssertEqual(ids.count, 3)
        XCTAssertNotNil(ids.first ?? nil)
        // A fresh id per attempt is the mutation this pins: it would bill three
        // clicks for one tap.
        XCTAssertEqual(Set(ids.compactMap { $0 }).count, 1)
    }

    func testThreeTransientFailuresSurfaceOneNetworkError() {
        let dropped = URLError(.notConnectedToInternet)
        let t = InlineTransport { request in
            guard request.url?.path.contains("/links/resolve/") == true else {
                return Self.validated(request)
            }
            return (nil, nil, dropped)
        }

        let results = Results()
        configure(t) { results.append($0) }
        XCTAssertTrue(WarpLink.open(tapped))

        XCTAssertEqual(t.requestCount(forPathContaining: "/links/resolve/"), 3)
        XCTAssertEqual(results.all.count, 1)
        guard case .failure(.networkError) = results.all.first else {
            return XCTFail("expected networkError, got \(String(describing: results.all.first))")
        }
        // WL-S21 stands. The host sees the error it always saw; the only change
        // is that it now means "failed after the bounded retries".
        XCTAssertEqual(recorder.delays.count, 2)
        XCTAssertLessThan(recorder.delays.reduce(0, +), RetryPolicy.totalBudget)
    }

    func testARefusalIsNotRetried() {
        for (code, body) in [
            (404, [:] as [String: Any]),
            (403, ["error": ["code": "PASSWORD_REQUIRED"]] as [String: Any]),
            (410, [:] as [String: Any]),
        ] {
            WarpLink.reset()
            recorder = ScheduleRecorder()
            let answer = Self.status(code, body: body)
            let t = InlineTransport { request in
                guard request.url?.path.contains("/links/resolve/") == true else {
                    return Self.validated(request)
                }
                return answer(request)
            }
            configure(t) { _ in }
            XCTAssertTrue(WarpLink.open(tapped))

            // A 410 matters as much as the 404: the resolve parser collapses it
            // into .serverError through its `default:` branch, so a rule of
            // "retry every serverError" would retry an expired link.
            XCTAssertEqual(
                t.requestCount(forPathContaining: "/links/resolve/"), 1,
                "status \(code) must not be retried"
            )
        }
    }

    // MARK: - Superseding

    func testANewerTapSilencesTheOlderOne() {
        // The second tap resolves; the first is superseded while it waits.
        let seenFirst = Flag()
        let t = InlineTransport { request in
            guard request.url?.path.contains("/links/resolve/") == true else {
                return Self.validated(request)
            }
            if request.url?.absoluteString.contains("abc123") == true {
                seenFirst.raise()
                return (nil, nil, URLError(.networkConnectionLost))
            }
            return Self.ok(request)
        }

        let results = Results()
        makeSDKSynchronous(t)
        recorder.install()
        // A superseding tap has to arrive while the first is waiting, and the
        // recorder runs the wait inline, so the second tap is issued from
        // inside the first's scheduled block.
        SDKEnvironment.schedule = { _, work in
            if seenFirst.isRaised { _ = WarpLink.open(URL(string: "https://aplnk.to/second")!) }
            work()
        }
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeferredCheck: false, onLink: { results.append($0) }
        ))
        XCTAssertTrue(WarpLink.open(tapped))

        // Exactly one delivery, and it is the newer tap's.
        XCTAssertEqual(results.all.count, 1)
        guard case .success(let link?)? = results.all.first else {
            return XCTFail("expected the newer tap's link")
        }
        XCTAssertEqual(link.linkId, "550e8400-e29b-41d4-a716-446655440000")
        // And the superseded tap stopped attempting rather than merely going
        // quiet: three requests for abc123 would mean it retried anyway.
        XCTAssertEqual(
            t.requests.filter { $0.url?.absoluteString.contains("abc123") == true }.count, 1,
            "a superseded tap must stop retrying"
        )
    }

    func testANewerTapCancelsWhatTheOlderTapLeftOnTheWire() {
        // The half `InlineTransport` cannot show: a request that is still open
        // when the next tap arrives. Ignoring its answer is not enough, because
        // the connection stays up for the whole timeout on the network least
        // able to spare it.
        let t = PendingTransport()
        SDKEnvironment.makeTransport = { t }
        SDKEnvironment.deliver = { work in work() }
        SDKEnvironment.schedule = { _, work in work() }

        let results = Results()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeferredCheck: false, onLink: { results.append($0) }
        ))

        XCTAssertTrue(WarpLink.open(tapped))
        XCTAssertEqual(t.pending.count, 1)
        XCTAssertTrue(WarpLink.open(URL(string: "https://aplnk.to/second")!))

        XCTAssertEqual(t.pending.count, 2)
        XCTAssertTrue(t.pending[0].cancelled, "the older tap's request must be stopped")
        XCTAssertFalse(t.pending[1].cancelled, "the newer tap's request must be left alone")
        XCTAssertEqual(results.all.count, 0, "neither request has answered yet")
    }

    func testAnAttemptRecordedAfterItsTapWasSupersededIsCancelledAtOnce() {
        configure(transport(resolveScript: [])) { _ in }
        let generation = WarpLink.supersedeInFlightTap()
        _ = WarpLink.supersedeInFlightTap()

        let task = PendingTransport.Pending()
        WarpLink.setInFlightTap(task, generation: generation)

        // Superseded between issuing the attempt and recording its handle.
        // Dropped on the floor it would hold its connection for a whole timeout.
        XCTAssertTrue(task.cancelled)
    }

    func testAManualResolveIsNeverCancelledBySupersede() {
        configure(transport(resolveScript: [])) { _ in }
        let task = PendingTransport.Pending()
        WarpLink.setInFlightTap(task, generation: nil)

        _ = WarpLink.supersedeInFlightTap()

        XCTAssertFalse(task.cancelled, "a manual handleDeepLink caller is owed its answer")
    }

    func testASupersededManualCallerStillGetsItsAnswer() {
        // `handleDeepLink` is a public API. A tap arriving while it resolves
        // must not silence it and must not cut its retries short.
        let superseded = Flag()
        let t = InlineTransport { request in
            guard request.url?.path.contains("/links/resolve/") == true else {
                return Self.validated(request)
            }
            guard superseded.isRaised else {
                superseded.raise()
                _ = WarpLink.supersedeInFlightTap()
                return (nil, nil, URLError(.networkConnectionLost))
            }
            return Self.ok(request)
        }

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
            "a manual caller is never superseded, so its retry still ran"
        )
    }

    // MARK: - The dedupe claim

    func testAFailedResolveReleasesTheDedupeClaimSoTheUserCanReTap() {
        let dropped = URLError(.notConnectedToInternet)
        let failures = Budget(3)
        let t = InlineTransport { request in
            guard request.url?.path.contains("/links/resolve/") == true else {
                return Self.validated(request)
            }
            return failures.spend() ? (nil, nil, dropped) : Self.ok(request)
        }

        let results = Results()
        configure(t) { results.append($0) }

        XCTAssertTrue(WarpLink.open(tapped))
        // Immediately, inside the 1.0s dedupe window, the user taps again. Before
        // this fix the claim was still stamped and the re-tap was swallowed, so
        // a user on a flaky connection could not retry by hand either.
        XCTAssertTrue(WarpLink.open(tapped))

        XCTAssertEqual(results.all.count, 2)
        guard case .failure(.networkError) = results.all.first else {
            return XCTFail("expected the first tap to fail")
        }
        guard case .success(let link?)? = results.all.last else {
            return XCTFail("expected the re-tap to resolve, got \(String(describing: results.all.last))")
        }
        XCTAssertEqual(link.linkId, "550e8400-e29b-41d4-a716-446655440000")
    }

    // conformance: WL-S03
    func testASuccessfulResolveKeepsTheClaimSoADoubleDeliveryIsStillSuppressed() {
        let t = transport(resolveScript: [])
        let results = Results()
        configure(t) { results.append($0) }

        XCTAssertTrue(WarpLink.open(tapped))
        XCTAssertTrue(WarpLink.open(tapped))

        // WL-S03 must not regress: releasing on failure is not releasing always.
        XCTAssertEqual(t.requestCount(forPathContaining: "/links/resolve/"), 1)
        XCTAssertEqual(results.all.count, 1)
    }

    // conformance: WL-S27
    func testARetapOfTheSameLinkIsNotResolvedAThirdTime() {
        // Tap A hangs. At 1.5 s, OUTSIDE the 1.0 s window, the user taps the
        // SAME link again. Tap B stamps a fresh claim and cancels A, and A's
        // cancellation then runs the failure branch. Releasing the claim there
        // drops B's, and a host wired both ways (a delegate plus a manual
        // `open`, the WL-S03 case) lets B's own duplicate through. That
        // duplicate supersedes B and resolves a THIRD time under a NEW tap id,
        // so the tap id cannot collapse it: one tap, two requests, two clicks.
        let t = CancellingTransport(
            holding: 1,
            requestsForPathContaining: "/links/resolve/",
            thenAnswering: Self.ok
        )
        var clock: TimeInterval = 0
        SDKEnvironment.makeTransport = { t }
        SDKEnvironment.deliver = { work in work() }
        SDKEnvironment.schedule = { _, work in work() }
        WarpLink.monotonicNow = { clock }

        let results = Results()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeferredCheck: false, onLink: { results.append($0) }
        ))

        XCTAssertTrue(WarpLink.open(tapped), "tap A, left open on the wire")
        clock = 1.5
        XCTAssertTrue(WarpLink.open(tapped), "tap B, past the window, cancels A")
        // The host's other wiring, handing the SDK the same URL a second time.
        XCTAssertTrue(WarpLink.open(tapped), "the duplicate B must be suppressed")

        let ids = tapIds(t.log)
        XCTAssertEqual(ids.count, 2, "tap A and tap B, and nothing after them")
        // From tap B onward: one request, one tap id, one delivery.
        XCTAssertEqual(Set(ids.dropFirst().compactMap { $0 }).count, 1)
        XCTAssertEqual(results.all.count, 1)
        guard case .success(let link?)? = results.all.first else {
            return XCTFail("expected tap B's link, got \(String(describing: results.all.first))")
        }
        XCTAssertEqual(link.linkId, "550e8400-e29b-41d4-a716-446655440000")
    }

    func testAFailedResolveLeavesANewerTapsClaimAlone() {
        // The claim belongs to whichever URL owns it now. Clearing it blindly
        // would let the newer link's own duplicate through.
        let t = transport(resolveScript: [])
        configure(t) { _ in }
        XCTAssertTrue(WarpLink.open(tapped))

        WarpLink.releaseDuplicateClaim(URL(string: "https://aplnk.to/second")!)

        XCTAssertTrue(
            WarpLink.shouldSuppressDuplicate(tapped),
            "a failed resolve of another link must not drop this link's claim"
        )
    }

    /// Not private: `HangingResolveProtocol` serves the same body.
    static let linkJSON: [String: Any] = [
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "slug": "abc123",
        "domain": "aplnk.to",
        "destination_url": "https://example.com",
        "ios_url": "myapp://page",
        "ios_fallback_url": NSNull(),
        "custom_params": [:],
        "created_at": "2026-01-01T00:00:00.000Z",
    ]
}
