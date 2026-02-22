import XCTest
@testable import WarpLink

final class WarpLinkOptionsTests: XCTestCase {

    func testDefaultValues() {
        let options = WarpLinkOptions()
        XCTAssertEqual(options.apiEndpoint, "https://api.warplink.app/v1")
        XCTAssertFalse(options.debugLogging)
        XCTAssertEqual(options.matchWindowHours, 72)
    }

    func testCustomValues() {
        let options = WarpLinkOptions(
            apiEndpoint: "https://custom.api.com/v2",
            debugLogging: true,
            matchWindowHours: 24
        )
        XCTAssertEqual(options.apiEndpoint, "https://custom.api.com/v2")
        XCTAssertTrue(options.debugLogging)
        XCTAssertEqual(options.matchWindowHours, 24)
    }

    func testPartialCustomization() {
        let options = WarpLinkOptions(debugLogging: true)
        XCTAssertEqual(options.apiEndpoint, "https://api.warplink.app/v1")
        XCTAssertTrue(options.debugLogging)
        XCTAssertEqual(options.matchWindowHours, 72)
    }
}
