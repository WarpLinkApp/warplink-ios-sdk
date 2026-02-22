import XCTest
@testable import WarpLink

final class WarpLinkConfigureTests: XCTestCase {

    private let validLiveKey = "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    private let validTestKey = "wl_test_x9y8z7w6v5u4t3s2r1q0p9o8n7m6l5k4"

    override func setUp() {
        super.setUp()
        WarpLink.reset()
    }

    override func tearDown() {
        WarpLink.reset()
        super.tearDown()
    }

    // MARK: - Format Validation

    func testInvalidApiKeyFormatRejected() {
        let invalidKeys = [
            "",
            "random-string",
            "wl_prod_a1b2c3d4e5f6g7h8i9j0k1l2m3n4",
            "wl_live_tooshort",
            "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4extra",
            "wl_test_a1b2c3d4e5f6g7h8!9j0k1l2m3n4",
        ]
        for key in invalidKeys {
            WarpLink.reset()
            WarpLink.configure(apiKey: key)
            XCTAssertFalse(
                WarpLink.isConfigured,
                "Key should be rejected: \(key)"
            )
        }
    }

    func testValidLiveKeyAccepted() {
        WarpLink.configure(apiKey: validLiveKey)
        XCTAssertTrue(WarpLink.isConfigured)
    }

    func testValidTestKeyAccepted() {
        WarpLink.configure(apiKey: validTestKey)
        XCTAssertTrue(WarpLink.isConfigured)
    }

    // MARK: - SDK Version

    func testSdkVersionIsExposed() {
        XCTAssertEqual(WarpLink.sdkVersion, "0.1.0")
    }

    // MARK: - Reconfiguration

    func testSecondConfigureReplaces() {
        WarpLink.configure(apiKey: validLiveKey)
        XCTAssertTrue(WarpLink.isConfigured)

        WarpLink.configure(apiKey: validTestKey)
        XCTAssertTrue(WarpLink.isConfigured)
    }

    // MARK: - Service Wiring

    func testConfigureCreatesInternalServices() {
        WarpLink.configure(apiKey: validLiveKey)
        XCTAssertTrue(WarpLink.isConfigured)
    }

    func testResetClearsAllState() {
        WarpLink.configure(apiKey: validLiveKey)
        XCTAssertTrue(WarpLink.isConfigured)

        WarpLink.reset()
        XCTAssertFalse(WarpLink.isConfigured)
    }

    // MARK: - Thread Safety

    func testConcurrentConfigureDoesNotCrash() {
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            WarpLink.configure(apiKey: validLiveKey)
        }
        XCTAssertTrue(WarpLink.isConfigured)
    }

    func testRapidReconfigurationDoesNotLeak() {
        for _ in 0..<1000 {
            WarpLink.configure(apiKey: validLiveKey)
        }
        XCTAssertTrue(WarpLink.isConfigured)
    }
}
