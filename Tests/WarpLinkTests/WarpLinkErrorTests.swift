import XCTest
@testable import WarpLink

final class WarpLinkErrorTests: XCTestCase {

    func testInvalidApiKeyFormatError() {
        let error = WarpLinkError.invalidApiKeyFormat
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(
            error.errorDescription!.contains("wl_live_"),
            "Error description should mention 'wl_live_' prefix"
        )
        XCTAssertTrue(
            error.errorDescription!.contains("wl_test_"),
            "Error description should mention 'wl_test_' prefix"
        )
        XCTAssertTrue(
            error.errorDescription!.contains("32 alphanumeric"),
            "Error description should mention '32 alphanumeric'"
        )
    }

    func testNotConfiguredError() {
        let error = WarpLinkError.notConfigured
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(
            error.errorDescription!.contains("not configured"),
            "Error description should mention 'not configured'"
        )
    }

    func testNetworkError() {
        let underlying = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet
        )
        let error = WarpLinkError.networkError(underlying)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(
            error.errorDescription!.contains("Network error"),
            "Error description should mention 'Network error'"
        )
    }

    func testServerError() {
        let error = WarpLinkError.serverError(
            statusCode: 429,
            message: "Rate limit exceeded"
        )
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(
            error.errorDescription!.contains("429"),
            "Error description should contain status code"
        )
        XCTAssertTrue(
            error.errorDescription!.contains("Rate limit exceeded"),
            "Error description should contain message"
        )
    }

    func testMatchTypeRawValues() {
        XCTAssertEqual(MatchType.deterministic.rawValue, "deterministic")
        XCTAssertEqual(MatchType.probabilistic.rawValue, "probabilistic")
    }
}
