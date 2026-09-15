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

    // conformance: WL-S11
    func testInvalidApiKeyFormatDispatchedToOnLink() {
        // Cross-SDK parity: a malformed key is reported via onLink (Android does
        // the same), not silently swallowed. Dispatched async on the main queue.
        let expectation = expectation(description: "onLink receives format error")
        // A Counter rather than a captured `var`. onLink is dispatched, so the
        // closure is concurrently executing and mutating a local from inside it
        // does not compile under strict concurrency checking. Counting also says
        // more than a flag did: exactly one dispatch, not at least one.
        let formatErrors = Counter()
        let options = WarpLinkOptions(onLink: { result in
            if case .failure(.invalidApiKeyFormat) = result {
                formatErrors.increment()
            }
            expectation.fulfill()
        })
        WarpLink.configure(apiKey: "wl_live_tooshort", options: options)
        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(formatErrors.value, 1)
        XCTAssertFalse(WarpLink.isConfigured)
    }

    // The other half of the malformed-key parity scenario claimed above: the
    // warning, which is emitted even when nothing is listening.
    func testAMalformedKeyAlwaysWarns() throws {
        var lines: [String] = []
        let logger = Logger(debugEnabled: false, sink: { lines.append($0) })

        WarpLink.reportInvalidKeyFormat("wl_live_short", options: WarpLinkOptions(), logger: logger)

        // Debug logging is off and there is no onLink: this line is the ONLY
        // signal the developer gets. Downgrading warn() to log() stayed green.
        XCTAssertEqual(lines.count, 1)
        // Unwrapped rather than subscripted: XCTAssert does not stop the test,
        // so lines[0] on an empty array would trap and take every class after
        // this one down with it.
        let warning = try XCTUnwrap(lines.first)
        XCTAssertTrue(warning.contains("WARNING"))
        XCTAssertTrue(warning.contains("Invalid API key format"))
    }

    func testValidLiveKeyAccepted() {
        WarpLink.configure(apiKey: validLiveKey, options: TestSupport.noAuto)
        XCTAssertTrue(WarpLink.isConfigured)
    }

    func testValidTestKeyAccepted() {
        WarpLink.configure(apiKey: validTestKey, options: TestSupport.noAuto)
        XCTAssertTrue(WarpLink.isConfigured)
    }

    // MARK: - SDK Version

    func testSdkVersionIsExposed() {
        XCTAssertEqual(WarpLink.sdkVersion, "1.1.0")
    }

    // MARK: - Reconfiguration

    func testSecondConfigureReplaces() {
        WarpLink.configure(apiKey: validLiveKey, options: TestSupport.noAuto)
        XCTAssertTrue(WarpLink.isConfigured)

        WarpLink.configure(apiKey: validTestKey, options: TestSupport.noAuto)
        XCTAssertTrue(WarpLink.isConfigured)
    }

    // MARK: - Service Wiring

    func testConfigureCreatesInternalServices() {
        WarpLink.configure(apiKey: validLiveKey, options: TestSupport.noAuto)
        XCTAssertTrue(WarpLink.isConfigured)
    }

    func testResetClearsAllState() {
        WarpLink.configure(apiKey: validLiveKey, options: TestSupport.noAuto)
        XCTAssertTrue(WarpLink.isConfigured)

        WarpLink.reset()
        XCTAssertFalse(WarpLink.isConfigured)
    }

    // MARK: - Thread Safety

    func testConcurrentConfigureDoesNotCrash() {
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            WarpLink.configure(apiKey: validLiveKey, options: TestSupport.noAuto)
        }
        XCTAssertTrue(WarpLink.isConfigured)
    }

    func testRapidReconfigurationDoesNotLeak() {
        for _ in 0..<1000 {
            WarpLink.configure(apiKey: validLiveKey, options: TestSupport.noAuto)
        }
        XCTAssertTrue(WarpLink.isConfigured)
    }
}
