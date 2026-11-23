import XCTest
@testable import WarpLink

/// When the SDK waits for the app to become active, and when there is nothing to wait for.
final class AppForegroundTests: XCTestCase {

    private func decide(
        hasApplication: Bool = true, isExtension: Bool = false,
        isActive: Bool = false, underTests: Bool = false
    ) -> AppForeground.Disposition {
        AppForeground.disposition(
            hasApplication: hasApplication, isExtension: isExtension,
            isActive: isActive, underTests: underTests
        )
    }

    func testAnInactiveAppWaitsForActivation() {
        XCTAssertEqual(decide(), .waitForActivation)
    }

    func testAnActiveAppRunsAtOnce() {
        XCTAssertEqual(decide(isActive: true), .runNow)
    }

    func testWithoutAnAppObjectTheCheckRunsAtOnce() {
        XCTAssertEqual(decide(hasApplication: false), .runNow)
    }

    func testAnAppExtensionRunsAtOnce() {
        XCTAssertEqual(decide(isExtension: true), .runNow)
    }

    func testAnInactiveProcessUnderXCTestRunsAtOnce() {
        XCTAssertEqual(decide(underTests: true), .runNow, "a customer test must not wait for an activation")
    }

    func testThisTestProcessIsRecognisedAsXCTest() {
        XCTAssertNotNil(NSClassFromString("XCTestCase"))
    }
}
