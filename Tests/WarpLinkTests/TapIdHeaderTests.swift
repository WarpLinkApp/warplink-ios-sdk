import XCTest
@testable import WarpLink

/// The tap id header and the per-attempt timeout, read off the `URLRequest` the
/// SDK actually built.
///
/// `InlineTransport` hands back the request untouched, so what is asserted here
/// is what the builder produced rather than what a `URLSession` chose to send.
/// That is what makes "absent unless asked for" provable: through a session the
/// default timeout is the session configuration's, not the request's.
final class TapIdHeaderTests: XCTestCase {

    private let tapId = "0b6e7a3c-6c5a-4a2e-9f0e-2d9a1c7b4e11"
    private var transport: InlineTransport!
    private var client: APIClient!

    private let signals = DeviceSignals(
        acceptLanguage: "en-US", timezoneOffset: -300, timezone: "America/Toronto"
    )

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        transport = InlineTransport.serving { _ in ["matched": false] }
        makeSDKSynchronous(transport)
        client = APIClient(
            apiKey: "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
            baseURL: "https://api.warplink.app/v1",
            transport: transport
        )
    }

    override func tearDown() {
        WarpLink.reset()
        client = nil
        transport = nil
        super.tearDown()
    }

    // MARK: - Attribution

    func testTheTapIdTravelsOnTheAttributionRequest() {
        // Log-only on this endpoint, and sent anyway so one attribution attempt
        // is traceable across its retries.
        match(tapId: tapId)
        XCTAssertEqual(sentTapId, tapId)
    }

    func testNoTapIdMeansNoHeaderOnTheAttributionRequest() {
        match()
        XCTAssertNil(sentTapId)
    }

    func testTheAttemptTimeoutReachesTheAttributionRequest() {
        match(timeout: 3)
        XCTAssertEqual(transport.requests.last?.timeoutInterval, 3)
    }

    func testAttributionWithoutATimeoutLeavesTheRequestDefault() {
        // Pins "only when asked". A builder that always stamped a timeout would
        // pass every test that supplies one.
        match()
        XCTAssertEqual(transport.requests.last?.timeoutInterval, defaultTimeout)
    }

    // MARK: - Resolve

    func testResolveWithoutATimeoutLeavesTheRequestDefault() {
        client.resolveLink(slug: "abc123", domain: "aplnk.to") { _ in }
        XCTAssertEqual(transport.requests.last?.timeoutInterval, defaultTimeout)
    }

    // MARK: - Helpers

    /// `URLRequest`'s own untouched default, rather than the 60 that happens to
    /// be its value today.
    private var defaultTimeout: TimeInterval {
        URLRequest(url: URL(string: "https://api.warplink.app/v1")!).timeoutInterval
    }

    private var sentTapId: String? {
        transport.requests.last?.value(forHTTPHeaderField: APIClient.tapIdHeader)
    }

    private func match(tapId: String? = nil, timeout: TimeInterval? = nil) {
        client.matchAttribution(
            signals: signals,
            sdkVersion: "1.1.1",
            deviceId: nil,
            isReinstall: false,
            tapId: tapId,
            timeout: timeout
        ) { _ in }
    }
}
