import XCTest
@testable import WarpLink

final class WarpLinkTests: XCTestCase {

    override func setUp() {
        super.setUp()
        WarpLink.reset()
    }

    override func tearDown() {
        WarpLink.reset()
        super.tearDown()
    }

    func testIsConfiguredDefaultFalse() {
        XCTAssertFalse(WarpLink.isConfigured)
    }

    func testConfigureSetsIsConfigured() {
        WarpLink.configure(apiKey: "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6")
        XCTAssertTrue(WarpLink.isConfigured)
    }

    func testHandleDeepLinkFailsWhenNotConfigured() {
        let expectation = expectation(description: "completion called")
        let url = URL(string: "https://aplnk.to/test")!

        WarpLink.handleDeepLink(url) { result in
            switch result {
            case .failure(let error):
                if case .notConfigured = error {
                    // Expected
                } else {
                    XCTFail("Expected notConfigured, got \(error)")
                }
            case .success:
                XCTFail("Expected failure when not configured")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testCheckDeferredDeepLinkFailsWhenNotConfigured() {
        let expectation = expectation(description: "completion called")

        WarpLink.checkDeferredDeepLink { result in
            switch result {
            case .failure(let error):
                if case .notConfigured = error {
                    // Expected
                } else {
                    XCTFail("Expected notConfigured, got \(error)")
                }
            case .success:
                XCTFail("Expected failure when not configured")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func testConfigureWithOptions() {
        let options = WarpLinkOptions(
            apiEndpoint: "https://custom.api.com/v1",
            debugLogging: true,
            matchWindowHours: 48
        )
        WarpLink.configure(apiKey: "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6", options: options)
        XCTAssertTrue(WarpLink.isConfigured)
    }
}
