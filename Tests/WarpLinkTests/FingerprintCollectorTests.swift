import XCTest
@testable import WarpLink

final class FingerprintCollectorTests: XCTestCase {

    private var collector: FingerprintCollector!

    override func setUp() {
        super.setUp()
        collector = FingerprintCollector()
    }

    func testCollectFingerprintReturnsNonEmptyAcceptLanguage() {
        let exp = expectation(description: "completion")
        collector.collectFingerprint { result in
            switch result {
            case .success(let signals):
                XCTAssertFalse(signals.acceptLanguage.isEmpty)
            case .failure(let error):
                XCTFail("Expected success, got \(error)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testScreenDimensionsAreNonNegative() {
        let exp = expectation(description: "completion")
        collector.collectFingerprint { result in
            switch result {
            case .success(let signals):
                XCTAssertGreaterThanOrEqual(signals.screenWidth, 0)
                XCTAssertGreaterThanOrEqual(signals.screenHeight, 0)
            case .failure(let error):
                XCTFail("Expected success, got \(error)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testTimezoneOffsetIsValidInteger() {
        let exp = expectation(description: "completion")
        collector.collectFingerprint { result in
            switch result {
            case .success(let signals):
                // Valid timezone offsets range from -720 to +840 minutes
                XCTAssertGreaterThanOrEqual(signals.timezoneOffset, -720)
                XCTAssertLessThanOrEqual(signals.timezoneOffset, 840)
            case .failure(let error):
                XCTFail("Expected success, got \(error)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testDeterminism() {
        let exp1 = expectation(description: "first")
        let exp2 = expectation(description: "second")
        var first: DeviceSignals?
        var second: DeviceSignals?

        collector.collectFingerprint { result in
            if case .success(let signals) = result {
                first = signals
            }
            exp1.fulfill()
        }

        collector.collectFingerprint { result in
            if case .success(let signals) = result {
                second = signals
            }
            exp2.fulfill()
        }

        waitForExpectations(timeout: 2)
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(first?.acceptLanguage, second?.acceptLanguage)
        XCTAssertEqual(first?.screenWidth, second?.screenWidth)
        XCTAssertEqual(first?.screenHeight, second?.screenHeight)
        XCTAssertEqual(first?.timezoneOffset, second?.timezoneOffset)
        XCTAssertEqual(first?.userAgent, second?.userAgent)
    }

    func testUserAgentMatchesSDKFormat() {
        let exp = expectation(description: "completion")
        collector.collectFingerprint { result in
            switch result {
            case .success(let signals):
                XCTAssertTrue(
                    signals.userAgent.hasPrefix("WarpLink-iOS/"),
                    "Expected WarpLink-iOS/ prefix, got \(signals.userAgent)"
                )
            case .failure(let error):
                XCTFail("Expected success, got \(error)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }
}
