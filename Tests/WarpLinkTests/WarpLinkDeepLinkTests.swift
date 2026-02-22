import XCTest
@testable import WarpLink

final class WarpLinkDeepLinkTests: XCTestCase {

    func testDeepLinkInitialization() {
        let deepLink = WarpLinkDeepLink(
            linkId: "link-123",
            destination: "https://example.com",
            deepLinkUrl: "myapp://path/to/content",
            customParams: ["campaign": "summer", "source": "email"],
            isDeferred: true,
            matchType: .probabilistic,
            matchConfidence: 0.85
        )

        XCTAssertEqual(deepLink.linkId, "link-123")
        XCTAssertEqual(deepLink.destination, "https://example.com")
        XCTAssertEqual(deepLink.deepLinkUrl, "myapp://path/to/content")
        XCTAssertEqual(deepLink.customParams["campaign"] as? String, "summer")
        XCTAssertEqual(deepLink.customParams["source"] as? String, "email")
        XCTAssertTrue(deepLink.isDeferred)
        XCTAssertEqual(deepLink.matchType, .probabilistic)
        XCTAssertEqual(deepLink.matchConfidence, 0.85)
    }

    func testDeepLinkWithOptionalNils() {
        let deepLink = WarpLinkDeepLink(
            linkId: "link-456",
            destination: "https://example.com/page"
        )

        XCTAssertEqual(deepLink.linkId, "link-456")
        XCTAssertEqual(deepLink.destination, "https://example.com/page")
        XCTAssertNil(deepLink.deepLinkUrl)
        XCTAssertTrue(deepLink.customParams.isEmpty)
        XCTAssertFalse(deepLink.isDeferred)
        XCTAssertNil(deepLink.matchType)
        XCTAssertNil(deepLink.matchConfidence)
    }
}
