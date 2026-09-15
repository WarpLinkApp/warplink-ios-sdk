import XCTest
@testable import WarpLink

/// The deferred check gets the same bounded retry, and a final failure still
/// leaves the gate open for the next launch.
///
/// The gate is the load-bearing half. A failed attempt is deliberately not
/// marked complete, so the next launch tries again; leg 16 and leg iL16 both
/// hang off that, and `docs/deferred-deep-links.md` promises it. A bounded
/// retry sits UNDERNEATH that promise and must not disturb it. Closing the gate
/// on a retry-exhausted failure would cost a user who was offline at launch
/// their attribution permanently, which is a worse defect than the one this
/// whole change fixes.
final class DeferredCheckRetryTests: XCTestCase {

    private let apiKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
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

    // MARK: - Retrying

    func testATransientAttributionFailureThenASuccessAnswersOnce() {
        let dropped = URLError(.networkConnectionLost)
        let t = transport(attributionScript: [(nil, nil, dropped), (nil, nil, dropped)])
        let store = configure(t)

        let results = Results()
        WarpLink.checkDeferredDeepLink { results.append($0) }

        XCTAssertEqual(t.requestCount(forPathContaining: "/attribution/match"), 3)
        XCTAssertEqual(results.all.count, 1, "one check, one answer")
        guard case .success(let link)? = results.all.first else {
            return XCTFail("expected the third attempt's answer, got \(String(describing: results.all.first))")
        }
        XCTAssertNil(link)
        XCTAssertEqual(recorder.delays.count, 2)
        XCTAssertLessThan(recorder.delays.reduce(0, +), RetryPolicy.totalBudget)
        // A confirmed no-match still closes the gate. Only a run that FAILS
        // leaves it open, so this pins the other half of the rule too.
        XCTAssertTrue(store.isAttributionComplete)
    }

    func testEveryAttemptOfOneCheckCarriesTheSameTapId() {
        let dropped = URLError(.networkConnectionLost)
        let t = transport(attributionScript: [(nil, nil, dropped), (nil, nil, dropped)])
        configure(t)
        WarpLink.checkDeferredDeepLink { _ in }

        let ids = t.requests
            .filter { $0.url?.path.contains("/attribution/match") == true }
            .map { $0.value(forHTTPHeaderField: APIClient.tapIdHeader) }
        XCTAssertEqual(ids.count, 3)
        XCTAssertNotNil(ids.first ?? nil, "the tap id travels on the attribution request")
        // Log-only on this endpoint. `app_installs.click_id` is uniquely
        // indexed, but the server derives its value from the deferred payload
        // rather than from the client, so a fresh id per attempt would not
        // overbill here. It would only make one check untraceable across its
        // own retries.
        XCTAssertEqual(Set(ids.compactMap { $0 }).count, 1)
    }

    func testEveryAttemptOfTheCheckIsBounded() {
        let dropped = URLError(.networkConnectionLost)
        let t = transport(attributionScript: [(nil, nil, dropped), (nil, nil, dropped)])
        configure(t)
        WarpLink.checkDeferredDeepLink { _ in }

        let timeouts = t.requests
            .filter { $0.url?.path.contains("/attribution/match") == true }
            .map { $0.timeoutInterval }
        // Attempt 1 included. Unbounded it inherits URLSession's 60 second
        // default, and on the network this exists for the first attempt hangs
        // rather than fails, so the budget would be spent before any retry ran.
        XCTAssertEqual(timeouts, [
            RetryPolicy.firstAttemptTimeout,
            RetryPolicy.retryAttemptTimeout,
            RetryPolicy.retryAttemptTimeout,
        ])
    }

    func testARefusedAttributionIsNotRetried() {
        // 401 and 403 are `.invalidApiKey`: a verdict the server will repeat.
        for code in [401, 403] {
            WarpLink.reset()
            recorder = ScheduleRecorder()
            let t = InlineTransport { request in
                guard request.url?.path.contains("/attribution/match") == true else {
                    return Self.validatedKey(request)
                }
                return Self.status(code, for: request)
            }
            configure(t)
            WarpLink.checkDeferredDeepLink { _ in }

            XCTAssertEqual(
                t.requestCount(forPathContaining: "/attribution/match"), 1,
                "status \(code) must not be retried"
            )
        }
    }

    // MARK: - The gate stays open

    func testThreeFailedAttemptsLeaveTheGateOpen() {
        let t = failingAttribution(URLError(.notConnectedToInternet))
        let store = configure(t)

        let results = Results()
        WarpLink.checkDeferredDeepLink { results.append($0) }

        XCTAssertEqual(t.requestCount(forPathContaining: "/attribution/match"), 3)
        guard case .failure(.networkError) = results.all.first else {
            return XCTFail("expected networkError, got \(String(describing: results.all.first))")
        }
        // Leg 16 and leg iL16 depend on this: three failed attempts are still
        // "did not complete", so the next launch tries again.
        XCTAssertFalse(store.isAttributionComplete, "a retry-exhausted failure must not close the gate")
        XCTAssertFalse(WarpLink.isAttributionComplete)
        // And "attempted" is still recorded, so the next launch logs a retry
        // rather than a first launch.
        XCTAssertTrue(store.hasAttemptedAttribution)
    }

    func testTheNextLaunchStillRunsAfterTheRetriesAreExhausted() {
        // Offline at launch, so all three attempts fail. Then the connection
        // comes back and the app is launched again.
        let offline = Budget(RetryPolicy.maxAttempts)
        let t = InlineTransport { request in
            guard request.url?.path.contains("/attribution/match") == true else {
                return Self.validatedKey(request)
            }
            return offline.spend()
                ? (nil, nil, URLError(.notConnectedToInternet))
                : Self.matched(request)
        }
        let store = configure(t)

        WarpLink.checkDeferredDeepLink { _ in }
        XCTAssertEqual(t.requestCount(forPathContaining: "/attribution/match"), 3)
        XCTAssertFalse(store.isAttributionComplete)

        // The next launch. The gate is open and nothing was cached, so the
        // check really goes back to the server and the install is attributed.
        let results = Results()
        WarpLink.checkDeferredDeepLink { results.append($0) }

        XCTAssertEqual(t.requestCount(forPathContaining: "/attribution/match"), 4)
        guard case .success(let link?)? = results.all.first else {
            return XCTFail(
                "expected the next launch to attribute, got \(String(describing: results.all.first))"
            )
        }
        XCTAssertEqual(link.linkId, "link-deferred-1")
        XCTAssertTrue(link.isDeferred)
        XCTAssertTrue(store.isAttributionComplete)
    }

    // MARK: - Superseding

    func testAReconfigureCancelsWhatTheCheckLeftOnTheWire() {
        let t = CancellingTransport(holdingPathContaining: "/attribution/match")
        SDKEnvironment.makeTransport = { t }
        SDKEnvironment.deliver = { work in work() }
        SDKEnvironment.schedule = { _, work in work() }
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(autoDeferredCheck: false))
        WarpLink.storage = freshStorage()

        let results = Results()
        WarpLink.checkDeferredDeepLink { results.append($0) }
        XCTAssertEqual(t.held.count, 1)
        XCTAssertFalse(t.held[0].cancelled)

        // Reconfiguring abandons that check. Ignoring its answer is not enough:
        // its connection would stay open for the whole of its timeout.
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(autoDeferredCheck: false))

        XCTAssertTrue(t.held[0].cancelled, "an abandoned check's request must be stopped")
        // And the cancellation it causes is not an error to show a user. The
        // abandoned check answers with the same no-op success its response path
        // uses, which `dispatchToOnLink` swallows.
        XCTAssertEqual(results.all.count, 1)
        guard case .success(let link)? = results.all.first, link == nil else {
            return XCTFail("expected the no-op success, got \(String(describing: results.all.first))")
        }
    }

    func testAnAttemptRecordedAfterItsCheckWasAbandonedIsCancelledAtOnce() {
        configure(transport(attributionScript: []))
        let generation = WarpLink.deferredCheckGeneration
        // Abandons that generation, exactly as a reconfigure does.
        WarpLink.reset()

        let task = PendingTransport.Pending()
        WarpLink.setInFlightDeferredCheck(task, generation: generation)

        // Abandoned between issuing the attempt and recording its handle.
        // Dropped on the floor it would hold its connection for a whole timeout.
        XCTAssertTrue(task.cancelled)
    }

    // MARK: - Helpers

    @discardableResult
    private func configure(_ transport: InlineTransport) -> Storage {
        makeSDKSynchronous(transport)
        recorder.install()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(autoDeferredCheck: false))
        let store = freshStorage()
        WarpLink.storage = store
        return store
    }

    /// A storage nothing outside this test can see. The real one writes a
    /// backup-excluded file and a Keychain item that would outlive the run and
    /// close this install's gate for every later run of the suite.
    private func freshStorage() -> Storage {
        let defaults = UserDefaults(suiteName: "DeferredCheckRetryTests")!
        defaults.removePersistentDomain(forName: "DeferredCheckRetryTests")
        return Storage(
            defaults: defaults,
            markerStore: InMemoryMarkerStore(),
            installMarkerStore: InMemoryMarkerStore()
        )
    }

    /// Answers `/sdk/validate` with a 200 and scripts the attribution responses,
    /// falling back to a confirmed no-match once the script runs out.
    private func transport(
        attributionScript: [(Data?, URLResponse?, Error?)]
    ) -> InlineTransport {
        var remaining = attributionScript
        return InlineTransport { request in
            guard request.url?.path.contains("/attribution/match") == true else {
                return Self.validatedKey(request)
            }
            return remaining.isEmpty ? Self.noMatch(request) : remaining.removeFirst()
        }
    }

    private func failingAttribution(_ error: URLError) -> InlineTransport {
        InlineTransport { request in
            guard request.url?.path.contains("/attribution/match") == true else {
                return Self.validatedKey(request)
            }
            return (nil, nil, error)
        }
    }

    private static func validatedKey(_ request: URLRequest) -> (Data?, URLResponse?, Error?) {
        json(["valid": true, "domains": ["aplnk.to"]], for: request)
    }

    private static func noMatch(_ request: URLRequest) -> (Data?, URLResponse?, Error?) {
        json(["matched": false], for: request)
    }

    private static func matched(_ request: URLRequest) -> (Data?, URLResponse?, Error?) {
        json([
            "matched": true,
            "link_id": "link-deferred-1",
            "destination_url": "https://example.com/welcome",
            "match_type": "fingerprint",
            "match_confidence": 0.9,
        ], for: request)
    }

    private static func json(
        _ body: [String: Any], for request: URLRequest
    ) -> (Data?, URLResponse?, Error?) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        return (try? JSONSerialization.data(withJSONObject: body), response, nil)
    }

    private static func status(
        _ code: Int, for request: URLRequest
    ) -> (Data?, URLResponse?, Error?) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil
        )!
        return (Data(), response, nil)
    }
}
