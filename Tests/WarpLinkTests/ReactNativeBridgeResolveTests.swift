import XCTest
@_spi(ReactNative) @testable import WarpLink

/// The React Native bridge resolves every tap through one native method, so
/// unlike `handleDeepLink` it must supersede and cancel on every call, the same
/// way Android's shared `resolveDeepLink` already does. And unlike `open()`,
/// the superseded call is a promise JS is awaiting, so it must still answer
/// rather than go quiet.
///
/// warplink-3f0f: without this, a superseded tap kept retrying on the wire for
/// its whole twelve second budget and could resolve successfully after JS had
/// already moved on, billing a link the user never saw delivered.
final class ReactNativeBridgeResolveTests: XCTestCase {

    private let apiKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    private let tapped = URL(string: "https://aplnk.to/abc123")!
    private let other = URL(string: "https://aplnk.to/second")!

    override func setUp() {
        super.setUp()
        WarpLink.reset()
    }

    override func tearDown() {
        WarpLink.reset()
        super.tearDown()
    }

    private func configureSynchronous(_ transport: HTTPTransport) {
        SDKEnvironment.makeTransport = { transport }
        SDKEnvironment.deliver = { work in work() }
        SDKEnvironment.schedule = { _, work in work() }
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(autoDeferredCheck: false))
    }

    // MARK: - Cancelling the wire

    // conformance: WL-S27
    func testASecondBridgeResolveCancelsTheFirstsOpenRequest() {
        let t = PendingTransport()
        configureSynchronous(t)

        WarpLink.resolveFromReactNativeBridge(tapped) { _ in }
        XCTAssertEqual(t.pending.count, 1)
        WarpLink.resolveFromReactNativeBridge(other) { _ in }

        XCTAssertEqual(t.pending.count, 2)
        XCTAssertTrue(t.pending[0].cancelled, "the superseded resolve's request must be stopped")
        XCTAssertFalse(t.pending[1].cancelled, "the newer resolve's request must be left alone")
    }

    // MARK: - Settling exactly once

    func testACancelledBridgeResolveStillSettlesWithANetworkError() {
        let t = CancellingTransport(holdingPathContaining: "/links/resolve/")
        configureSynchronous(t)

        var firstAnswer: Result<WarpLinkDeepLink, WarpLinkError>?
        WarpLink.resolveFromReactNativeBridge(tapped) { firstAnswer = $0 }
        XCTAssertNil(firstAnswer, "not superseded yet")

        var secondAnswer: Result<WarpLinkDeepLink, WarpLinkError>?
        WarpLink.resolveFromReactNativeBridge(other) { secondAnswer = $0 }

        guard case .failure(.networkError(let underlying)) = firstAnswer else {
            return XCTFail(
                "expected the superseded call to settle, got \(String(describing: firstAnswer))"
            )
        }
        XCTAssertEqual((underlying as? URLError)?.code, .cancelled)
        XCTAssertNil(secondAnswer, "the newer resolve is still on the wire")
    }

    // MARK: - Stopping retries

    // conformance: WL-S27
    func testASecondBridgeResolveStopsTheFirstsRetriesAndStillAnswersIt() {
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
        configureSynchronous(t)

        var firstAnswer: Result<WarpLinkDeepLink, WarpLinkError>?
        var secondAnswer: Result<WarpLinkDeepLink, WarpLinkError>?
        SDKEnvironment.schedule = { _, work in
            if seenFirst.isRaised {
                WarpLink.resolveFromReactNativeBridge(self.other) { secondAnswer = $0 }
            }
            work()
        }

        WarpLink.resolveFromReactNativeBridge(tapped) { firstAnswer = $0 }

        guard case .success(let link) = secondAnswer else {
            return XCTFail("expected the newer resolve to succeed, got \(String(describing: secondAnswer))")
        }
        XCTAssertEqual(link.linkId, "550e8400-e29b-41d4-a716-446655440000")
        guard case .failure = firstAnswer else {
            return XCTFail("the superseded resolve must still settle, got \(String(describing: firstAnswer))")
        }
        XCTAssertEqual(
            t.requests.filter { $0.url?.absoluteString.contains("abc123") == true }.count, 1,
            "a superseded bridge resolve must stop retrying"
        )
    }

    // MARK: - The public contract stays untouched

    func testTwoManualHandleDeepLinkCallsNeverCancelEachOther() {
        let t = PendingTransport()
        configureSynchronous(t)

        WarpLink.handleDeepLink(tapped) { _ in }
        WarpLink.handleDeepLink(other) { _ in }

        XCTAssertEqual(t.pending.count, 2)
        XCTAssertFalse(t.pending[0].cancelled)
        XCTAssertFalse(t.pending[1].cancelled)
    }

    func testABridgeResolveNeverCancelsAManualHandleDeepLinkInFlight() {
        let t = PendingTransport()
        configureSynchronous(t)

        WarpLink.handleDeepLink(tapped) { _ in }
        WarpLink.resolveFromReactNativeBridge(other) { _ in }

        XCTAssertFalse(t.pending[0].cancelled, "a manual caller is owed its answer")
    }

    func testAManualHandleDeepLinkNeverCancelsABridgeResolveInFlight() {
        let t = PendingTransport()
        configureSynchronous(t)

        WarpLink.resolveFromReactNativeBridge(tapped) { _ in }
        WarpLink.handleDeepLink(other) { _ in }

        XCTAssertFalse(t.pending[0].cancelled, "a manual caller must never supersede anything")
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
}
