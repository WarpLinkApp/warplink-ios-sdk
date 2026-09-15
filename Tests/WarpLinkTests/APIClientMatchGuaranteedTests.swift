import XCTest
@testable import WarpLink

/// `matchGuaranteed` gates auto sign-in and personal data in host apps. Nothing
/// on iOS pinned how it is read off the wire, so flipping the default to true
/// stayed green while every probabilistic guess became a guarantee.
final class APIClientMatchGuaranteedTests: XCTestCase {

    override func setUp() {
        super.setUp()
        WarpLink.reset()
    }

    override func tearDown() {
        WarpLink.reset()
        super.tearDown()
    }

    private func match(_ body: [String: Any]) -> AttributionResponse? {
        let transport = InlineTransport.serving { _ in body }
        makeSDKSynchronous(transport)
        let client = APIClient(apiKey: "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6", transport: transport)
        var received: AttributionResponse?
        client.matchAttribution(
            signals: DeviceSignals(acceptLanguage: "en-US", timezoneOffset: -300, timezone: "America/Toronto"),
            sdkVersion: "1.1.0", deviceId: nil, isReinstall: false
        ) { result in
            if case .success(let response) = result { received = response }
        }
        return received
    }

    func testGuaranteedOnlyWhenTheServerSaysSo() {
        let base: [String: Any] = ["matched": true, "link_id": "lnk_1", "destination_url": "https://example.com"]
        XCTAssertEqual(match(base.merging(["match_guaranteed": true]) { $1 })?.matchGuaranteed, true)
        XCTAssertEqual(match(base.merging(["match_guaranteed": false]) { $1 })?.matchGuaranteed, false)
    }

    func testAnOmittedFlagNeverReadsAsGuaranteed() {
        // Older servers omit it. A probabilistic guess must not become a
        // guarantee by default.
        let body: [String: Any] = ["matched": true, "link_id": "lnk_1", "destination_url": "https://example.com"]
        XCTAssertEqual(match(body)?.matchGuaranteed, false)
    }
}
