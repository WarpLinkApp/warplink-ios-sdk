import XCTest
@testable import WarpLink

final class WarpLinkDeepLinkTests: XCTestCase {

    func testDeepLinkInitialization() {
        let deepLink = WarpLinkDeepLink(
            linkId: "link-123",
            destination: "https://example.com",
            deepLinkUrl: "myapp://path/to/content",
            customParams: ["campaign": .string("summer"), "source": .string("email")],
            isDeferred: true,
            matchType: .probabilistic,
            matchConfidence: 0.85
        )

        XCTAssertEqual(deepLink.linkId, "link-123")
        XCTAssertEqual(deepLink.destination, "https://example.com")
        XCTAssertEqual(deepLink.deepLinkUrl, "myapp://path/to/content")
        XCTAssertEqual(deepLink.customParams["campaign"]?.stringValue, "summer")
        XCTAssertEqual(deepLink.customParams["source"]?.stringValue, "email")
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

    func testDecodesCacheWrittenBeforeMatchGuaranteedExisted() throws {
        // An app upgrading from an SDK without the field has exactly this
        // payload sitting in its cached attribution. It must still decode, or
        // the stored match is lost on upgrade.
        let legacy = """
        {
          "linkId": "abc123",
          "destination": "https://example.com",
          "deepLinkUrl": "myapp://path",
          "customParams": {},
          "isDeferred": true,
          "matchType": "probabilistic",
          "matchConfidence": 0.65
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WarpLinkDeepLink.self, from: legacy)

        XCTAssertEqual(decoded.linkId, "abc123")
        XCTAssertEqual(decoded.matchConfidence, 0.65)
        // Missing must mean "not guaranteed", never the permissive direction.
        XCTAssertFalse(decoded.matchGuaranteed)
    }

    func testRoundTripsMatchGuaranteed() throws {
        let link = WarpLinkDeepLink(
            linkId: "abc123",
            destination: "https://example.com",
            matchType: .deterministic,
            matchConfidence: 1.0,
            matchGuaranteed: true
        )

        let data = try JSONEncoder().encode(link)
        let decoded = try JSONDecoder().decode(WarpLinkDeepLink.self, from: data)

        XCTAssertTrue(decoded.matchGuaranteed)
        XCTAssertEqual(decoded, link)
    }
}
