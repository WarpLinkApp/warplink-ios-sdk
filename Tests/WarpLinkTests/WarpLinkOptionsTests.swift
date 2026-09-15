import XCTest
@testable import WarpLink

final class WarpLinkOptionsTests: XCTestCase {

    func testDefaultValues() {
        let options = WarpLinkOptions()
        XCTAssertEqual(options.apiEndpoint, "https://api.warplink.app/v1")
        XCTAssertFalse(options.debugLogging)
        XCTAssertTrue(options.autoDeepLinkHandling, "opt-out: deep link handling on by default")
        XCTAssertTrue(options.autoDeferredCheck, "opt-out: deferred check on by default")
        XCTAssertEqual(options.linkDomains, [], "declaring link domains stays optional")
        XCTAssertNil(options.onLink)
    }

    func testCustomValues() {
        let options = WarpLinkOptions(
            apiEndpoint: "https://custom.api.com/v2",
            debugLogging: true,
            autoDeepLinkHandling: false,
            autoDeferredCheck: false,
            linkDomains: ["links.acme.com"],
            onLink: { _ in }
        )
        XCTAssertEqual(options.apiEndpoint, "https://custom.api.com/v2")
        XCTAssertTrue(options.debugLogging)
        XCTAssertFalse(options.autoDeepLinkHandling)
        XCTAssertFalse(options.autoDeferredCheck)
        XCTAssertEqual(options.linkDomains, ["links.acme.com"])
        XCTAssertNotNil(options.onLink)
    }

    func testPartialCustomization() {
        let options = WarpLinkOptions(debugLogging: true)
        XCTAssertEqual(options.apiEndpoint, "https://api.warplink.app/v1")
        XCTAssertTrue(options.debugLogging)
        XCTAssertTrue(options.autoDeepLinkHandling)
        XCTAssertTrue(options.autoDeferredCheck)
        XCTAssertNil(options.onLink)
    }

    func testExistingCallSitesCompileUnchanged() {
        // linkDomains is additive: every shape an integration already writes
        // still compiles and still means what it meant.
        XCTAssertEqual(WarpLinkOptions(debugLogging: true).linkDomains, [])
        XCTAssertEqual(WarpLinkOptions(onLink: { _ in }).linkDomains, [])
        XCTAssertEqual(
            WarpLinkOptions(autoDeepLinkHandling: false, autoDeferredCheck: false).linkDomains, []
        )
    }

    func testOnLinkOnlyConfiguration() {
        // The common opt-out shape: just an API key + a single sink.
        let options = WarpLinkOptions(onLink: { _ in })
        XCTAssertTrue(options.autoDeepLinkHandling)
        XCTAssertTrue(options.autoDeferredCheck)
        XCTAssertNotNil(options.onLink)
    }
}
