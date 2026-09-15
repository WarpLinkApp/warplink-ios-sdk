import XCTest
@testable import WarpLink

/// Accepts a resolve and never answers it, for the first `hangingAttempts`
/// requests, then answers normally. `/sdk/validate` is always answered.
///
/// This is the network the whole change exists for. An inline transport can
/// fail, but it cannot hang, and hanging is what a weak uplink actually does.
final class HangingResolveProtocol: URLProtocol {

    private static let lock = NSLock()
    private static var starts: [TimeInterval] = []

    static var hangingAttempts = 1

    static var resolveStarts: [TimeInterval] {
        lock.lock(); defer { lock.unlock() }
        return starts
    }

    static func reset() {
        lock.lock(); starts = []; lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard request.url?.path.contains("/links/resolve/") == true else {
            return answer(["valid": true, "domains": ["aplnk.to"]])
        }
        Self.lock.lock()
        Self.starts.append(ProcessInfo.processInfo.systemUptime)
        let seen = Self.starts.count
        Self.lock.unlock()
        // Accepted and never answered: no response, no error, nothing. The
        // attempt ends only when its own timeout fires, which is the point.
        guard seen > Self.hangingAttempts else { return }
        answer(BoundedResolveRetryTests.linkJSON)
    }

    private func answer(_ body: [String: Any]) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(
            self, didLoad: (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        )
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Attempt 1 is bounded by its own timeout, not by the platform's default.
final class FirstAttemptBoundedTests: XCTestCase {

    private let apiKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        HangingResolveProtocol.hangingAttempts = 1
        HangingResolveProtocol.reset()
    }

    override func tearDown() {
        WarpLink.reset()
        super.tearDown()
    }

    // conformance: WL-S27
    func testAnAttemptThatIsAcceptedAndNeverAnsweredIsBoundedByItsOwnTimeout() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingResolveProtocol.self]
        let session = URLSession(configuration: configuration)
        // Neither `makeSDKSynchronous` nor `ScheduleRecorder` here: this test
        // measures wall time, so closing the transport or the wait would defeat
        // the only thing it exists to prove.
        SDKEnvironment.makeTransport = { URLSessionTransport(session: session) }

        let delivered = expectation(description: "one delivery")
        let deliveries = Counter()
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeferredCheck: false,
            onLink: { _ in deliveries.increment(); delivered.fulfill() }
        ))

        let startedAt = ProcessInfo.processInfo.systemUptime
        XCTAssertTrue(WarpLink.open(URL(string: "https://aplnk.to/abc123")!))
        // Well above the budget and well below URLSession's 60 second default,
        // so an unbounded first attempt fails here instead of merely passing
        // slowly.
        wait(for: [delivered], timeout: 20)
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt

        XCTAssertEqual(deliveries.value, 1)
        let starts = HangingResolveProtocol.resolveStarts
        guard starts.count == 2 else {
            return XCTFail("expected exactly two requests, got \(starts.count)")
        }
        let gap = starts[1] - starts[0]
        // The retry starts when attempt 1's own timeout fires, about four
        // seconds, plus the half second wait.
        XCTAssertGreaterThan(gap, RetryPolicy.firstAttemptTimeout - 0.5)
        XCTAssertLessThan(elapsed, RetryPolicy.totalBudget)
    }
}
