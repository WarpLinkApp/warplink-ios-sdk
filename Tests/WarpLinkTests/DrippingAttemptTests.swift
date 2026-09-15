import XCTest
@testable import WarpLink

/// Answers the first `drippingAttempts` resolve requests with a 200 header and
/// then one body byte every half second, for ever. `/sdk/validate` and later
/// resolves are answered normally.
///
/// The failure `HangingResolveProtocol` cannot express. `timeoutInterval` is
/// `timeoutIntervalForRequest`, which bounds the gap BETWEEN bytes rather than
/// the response, so a connection that keeps trickling resets it for ever and the
/// attempt never ends on its own. A silent connection times out; a slow one does
/// not, and both are the same weak uplink.
final class DrippingResolveProtocol: URLProtocol {

    private static let lock = NSLock()
    private static var starts: [TimeInterval] = []

    static var drippingAttempts = 1

    /// When each resolve request began, so a test can measure the gap between
    /// an abandoned attempt and its successor.
    static var resolveStarts: [TimeInterval] {
        lock.lock(); defer { lock.unlock() }
        return starts
    }

    static func reset() {
        lock.lock(); starts = []; lock.unlock()
    }

    private let stopped = Flag()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// Ends the drip. `URLSession` calls this when the task is cancelled, which
    /// is exactly what the watchdog under test causes.
    override func stopLoading() { stopped.raise() }

    override func startLoading() {
        guard request.url?.path.contains("/links/resolve/") == true else {
            return answer(["valid": true, "domains": ["aplnk.to"]])
        }
        Self.lock.lock()
        Self.starts.append(ProcessInfo.processInfo.systemUptime)
        let seen = Self.starts.count
        Self.lock.unlock()
        guard seen > Self.drippingAttempts else { return drip() }
        answer(BoundedResolveRetryTests.linkJSON)
    }

    /// A 200 whose body never finishes arriving.
    private func drip() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "1000000"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            while !stopped.isRaised {
                client?.urlProtocol(self, didLoad: Data([0x20]))
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
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

/// An attempt is bounded in wall time, not merely between bytes.
final class DrippingAttemptTests: XCTestCase {

    private let apiKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        DrippingResolveProtocol.drippingAttempts = 1
        DrippingResolveProtocol.reset()
    }

    override func tearDown() {
        WarpLink.reset()
        super.tearDown()
    }

    // conformance: WL-S27
    func testAnAttemptThatKeepsReceivingBytesIsStillAbandonedAtItsOwnTimeout() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DrippingResolveProtocol.self]
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
        // Well above the budget, so an attempt that is never abandoned fails
        // here instead of merely passing slowly.
        wait(for: [delivered], timeout: 20)
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt

        XCTAssertEqual(deliveries.value, 1)
        let starts = DrippingResolveProtocol.resolveStarts
        guard starts.count == 2 else {
            return XCTFail("expected exactly two requests, got \(starts.count)")
        }
        let gap = starts[1] - starts[0]
        // Attempt 1 was receiving a byte every half second the whole time, so
        // nothing between bytes could end it. Only a bound on the attempt
        // itself does, at about four seconds, plus the half second wait.
        XCTAssertGreaterThan(gap, RetryPolicy.firstAttemptTimeout - 0.5)
        // Every part of the gap is named, so the 2.0 left over really is
        // slack for a loaded machine. The gap also holds the wait before the
        // retry and up to the whole jitter, and folding those into a single
        // constant spends the slack on them instead.
        XCTAssertLessThan(
            gap,
            RetryPolicy.firstAttemptTimeout + RetryPolicy.baseDelays[0]
                + RetryPolicy.maxJitter + 2.0
        )
        XCTAssertLessThan(elapsed, RetryPolicy.totalBudget)
    }
}
