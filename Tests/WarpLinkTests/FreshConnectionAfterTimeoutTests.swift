import XCTest
@testable import WarpLink

/// The retry an abandoned attempt buys is sent on a new connection.
///
/// Over HTTP/2 every request to one host shares one pooled connection, and the
/// watchdog stops an attempt by cancelling its task, which resets only that
/// stream. When the connection itself has died without a FIN, which is what a
/// NAT timeout or a network change leaves behind, the retry rides the same
/// dead connection as the attempt it replaces, and so does every attempt after
/// it. Measured on the React Native iOS simulator pass: once the one open
/// connection was silently cut, two taps each spent all three attempts, and the
/// proxy in front of the app saw no new connection for any of the six.
///
/// A timeout is the only failure that says the connection may be dead. A 5xx
/// arrived over it, so it is working, and dropping it would only buy a new
/// handshake. Bead: warplink-qr6k.
final class FreshConnectionAfterTimeoutTests: XCTestCase {

    private let apiKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    private let tapped = URL(string: "https://aplnk.to/abc123")!
    private var watchdog: ManualWatchdog!

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        watchdog = ManualWatchdog()
    }

    override func tearDown() {
        WarpLink.reset()
        watchdog = nil
        super.tearDown()
    }

    private func configure(
        _ transport: ConnectionTrackingTransport,
        onLink: @escaping @Sendable (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        SDKEnvironment.makeTransport = { transport }
        SDKEnvironment.deliver = { work in work() }
        SDKEnvironment.schedule = { _, work in work() }
        watchdog.install()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeferredCheck: false, onLink: onLink
        ))
    }

    // conformance: WL-S27
    func testTheRetryAfterATimedOutAttemptIsSentOnANewConnection() {
        let transport = ConnectionTrackingTransport(
            path: "/links/resolve/", firstAttempt: .hang, later: .answer(200, Self.linkJSON)
        )
        let results = Results()
        configure(transport) { results.append($0) }

        XCTAssertTrue(WarpLink.open(tapped))
        XCTAssertEqual(transport.events, ["request"], "attempt 1 is on the wire and has not answered")

        // Attempt 1's deadline arrives with no answer.
        watchdog.fireFirst()

        XCTAssertEqual(
            transport.events, ["request", "discard", "request"],
            "the connection attempt 1 was stuck on must be dropped before attempt 2 is sent"
        )
        XCTAssertEqual(results.all.count, 1, "one tap, one delivery")
        guard case .success(let link?)? = results.all.first else {
            return XCTFail("expected the retry's link, got \(String(describing: results.all.first))")
        }
        XCTAssertEqual(link.linkId, "550e8400-e29b-41d4-a716-446655440000")
    }

    // conformance: WL-S27
    func testTheRetryAfterAnOSCancelledAttemptIsSentOnANewConnection() {
        let transport = ConnectionTrackingTransport(
            path: "/links/resolve/", firstAttempt: .failCancelled, later: .answer(200, Self.linkJSON)
        )
        let results = Results()
        configure(transport) { results.append($0) }

        // No watchdog fires in this test: attempt 1 fails on its own, the way
        // the OS reports a connection that died while the app was suspended.
        XCTAssertTrue(WarpLink.open(tapped))

        XCTAssertEqual(
            transport.events, ["request", "discard", "request"],
            "an OS-cancelled attempt's connection must be dropped before the retry, same as a timeout"
        )
        XCTAssertEqual(results.all.count, 1, "one tap, one delivery")
        guard case .success(let link?)? = results.all.first else {
            return XCTFail("expected the retry's link, got \(String(describing: results.all.first))")
        }
        XCTAssertEqual(link.linkId, "550e8400-e29b-41d4-a716-446655440000")
    }

    // conformance: WL-S27
    func testAServerErrorKeepsTheConnectionItArrivedOver() {
        let transport = ConnectionTrackingTransport(
            path: "/links/resolve/", firstAttempt: .answer(503, [:]), later: .answer(200, Self.linkJSON)
        )
        let results = Results()
        configure(transport) { results.append($0) }

        XCTAssertTrue(WarpLink.open(tapped))

        XCTAssertEqual(
            transport.events, ["request", "request"],
            "a 5xx proves the connection works, so the retry reuses it"
        )
        XCTAssertEqual(results.all.count, 1)
    }

    // conformance: WL-S27
    func testTheDeferredCheckRetriesOnANewConnectionAfterATimeout() {
        let transport = ConnectionTrackingTransport(
            path: "/attribution/match", firstAttempt: .hang, later: .answer(200, ["matched": false])
        )
        SDKEnvironment.makeTransport = { transport }
        SDKEnvironment.deliver = { work in work() }
        SDKEnvironment.schedule = { _, work in work() }
        watchdog.install()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(autoDeferredCheck: false))
        WarpLink.storage = freshStorage()

        let results = Results()
        WarpLink.checkDeferredDeepLink { results.append($0) }
        XCTAssertEqual(transport.events, ["request"], "attempt 1 is on the wire and has not answered")

        watchdog.fireFirst()

        XCTAssertEqual(
            transport.events, ["request", "discard", "request"],
            "the same watchdog bounds the deferred check, so the same rule applies"
        )
        XCTAssertEqual(results.all.count, 1, "one check, one answer")
        guard case .success(let link)? = results.all.first else {
            return XCTFail("expected the retry's no-match, got \(String(describing: results.all.first))")
        }
        XCTAssertNil(link)
    }

    // conformance: WL-S27
    func testTheDeferredCheckRetriesOnANewConnectionAfterAnOSCancelledAttempt() {
        let transport = ConnectionTrackingTransport(
            path: "/attribution/match", firstAttempt: .failCancelled, later: .answer(200, ["matched": false])
        )
        SDKEnvironment.makeTransport = { transport }
        SDKEnvironment.deliver = { work in work() }
        SDKEnvironment.schedule = { _, work in work() }
        watchdog.install()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(autoDeferredCheck: false))
        WarpLink.storage = freshStorage()

        let results = Results()
        WarpLink.checkDeferredDeepLink { results.append($0) }

        XCTAssertEqual(
            transport.events, ["request", "discard", "request"],
            "the same rule applies to the deferred check's own retry"
        )
        XCTAssertEqual(results.all.count, 1, "one check, one answer")
        guard case .success(let link)? = results.all.first else {
            return XCTFail("expected the retry's no-match, got \(String(describing: results.all.first))")
        }
        XCTAssertNil(link)
    }

    /// What the shipped transport does when told to drop its connections.
    ///
    /// It moves to a new session, because a new session has no pooled
    /// connection to reuse, and it builds that session from the old one's
    /// configuration, so a host's own session (pinning, a custom protocol, a
    /// proxy) keeps working. It never invalidates a session it did not make:
    /// a host that handed over `.shared` or its own session is still using it.
    func testANewConnectionKeepsTheHostsConfigurationAndLeavesTheHostsSessionAlone() {
        let configuration = URLSessionConfiguration.ephemeral
        // Answers `/sdk/validate` at once, and stands in for the host's own
        // protocol: if the new session lost it, the request would go to the
        // real network instead.
        configuration.protocolClasses = [HangingResolveProtocol.self]
        let hostSession = URLSession(configuration: configuration)
        let transport = URLSessionTransport(session: hostSession)
        let validate = URL(string: "https://api.warplink.app/v1/sdk/validate")!

        transport.discardConnections()

        XCTAssertFalse(
            transport.currentSession === hostSession,
            "the next request needs a session with no pooled connection"
        )
        let answered = expectation(description: "answered through the host's protocol")
        transport.send(URLRequest(url: validate)) { _, response, _ in
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            answered.fulfill()
        }
        let hostStillWorks = expectation(description: "the host's session was not invalidated")
        hostSession.dataTask(with: validate) { _, response, _ in
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            hostStillWorks.fulfill()
        }.resume()
        wait(for: [answered, hostStillWorks], timeout: 5)
    }

    private static let linkJSON = BoundedResolveRetryTests.linkJSON

    /// A storage nothing outside this test can see, so the check's gate never
    /// closes for a later run of the suite.
    private func freshStorage() -> Storage {
        let defaults = UserDefaults(suiteName: "FreshConnectionAfterTimeoutTests")!
        defaults.removePersistentDomain(forName: "FreshConnectionAfterTimeoutTests")
        return Storage(
            defaults: defaults,
            markerStore: InMemoryMarkerStore(),
            installMarkerStore: InMemoryMarkerStore()
        )
    }
}

// MARK: - Doubles

/// Every attempt's watchdog, armed and never fired on its own.
///
/// The test fires attempt 1's by hand, at the moment it wants that attempt
/// abandoned. Later attempts are armed too and never fire, so the retry has
/// every chance to answer.
final class ManualWatchdog {

    private struct Disarmed: ScheduledWork {
        func cancel() {}
    }

    private let lock = NSLock()
    private var armed: [() -> Void] = []

    /// Undone by `WarpLink.reset()`.
    func install() {
        SDKEnvironment.armWatchdog = { [weak self] _, work in
            self?.lock.lock()
            self?.armed.append(work)
            self?.lock.unlock()
            return Disarmed()
        }
    }

    func fireFirst() {
        lock.lock()
        let work = armed.first
        lock.unlock()
        work?()
    }
}

/// A transport with one connection: it records each request sent over it and
/// each time it is told to drop it, in order.
///
/// The first matching request is held with no answer and no error, the way a
/// request on a dead connection is held. Cancelling it answers
/// `URLError(.cancelled)`, exactly as `URLSession` does. Every later matching
/// request is answered from `later`. Anything else, `/sdk/validate` included,
/// is answered 200 and not recorded.
final class ConnectionTrackingTransport: HTTPTransport {

    enum Answer {
        case hang
        case answer(Int, [String: Any])
        /// What the OS reports for a connection that died while the app was
        /// suspended: the request fails on its own, never through this SDK's
        /// own `.cancel()`. Bead: warplink-i7oa.
        case failCancelled
    }

    private let lock = NSLock()
    private var log: [String] = []
    private var sent = 0
    private let path: String
    private let firstAttempt: Answer
    private let later: Answer

    init(path: String, firstAttempt: Answer, later: Answer) {
        self.path = path
        self.firstAttempt = firstAttempt
        self.later = later
    }

    var events: [String] {
        lock.lock(); defer { lock.unlock() }
        return log
    }

    private func record(_ event: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        log.append(event)
        if event == "request" { sent += 1 }
        return sent
    }

    func discardConnections() {
        _ = record("discard")
    }

    @discardableResult
    func send(
        _ request: URLRequest,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> HTTPTask {
        guard request.url?.path.contains(path) == true else {
            completion(Self.body(["valid": true, "domains": ["aplnk.to"]]), Self.status(200, request), nil)
            return CompletedHTTPTask()
        }
        let number = record("request")
        switch number == 1 ? firstAttempt : later {
        case .hang:
            return CancellingTransport.Held(completion: completion)
        case let .answer(code, body):
            completion(Self.body(body), Self.status(code, request), nil)
            return CompletedHTTPTask()
        case .failCancelled:
            completion(nil, nil, URLError(.cancelled))
            return CompletedHTTPTask()
        }
    }

    private static func body(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object)
    }

    private static func status(_ code: Int, _ request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
    }
}
