import XCTest
@testable import WarpLink

final class KeyEnvironmentTests: XCTestCase {

    func testATestKeyIsTest() {
        XCTAssertEqual(KeyEnvironment(apiKey: "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"), .test)
    }

    func testALiveKeyIsProduction() {
        XCTAssertEqual(KeyEnvironment(apiKey: "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"), .production)
    }

    func testAnyOtherPrefixKeepsTodaysBehaviourAsProduction() {
        XCTAssertEqual(KeyEnvironment(apiKey: "wl_staging_abc"), .production)
        XCTAssertEqual(KeyEnvironment(apiKey: "WL_TEST_abc"), .production)
        XCTAssertEqual(KeyEnvironment(apiKey: ""), .production)
    }

    func testProductionKeepsEveryNameAndTestGetsItsOwn() {
        XCTAssertEqual(KeyEnvironment.production.scoped("warplink_cached_domains"), "warplink_cached_domains")
        XCTAssertEqual(KeyEnvironment.test.scoped("warplink_cached_domains"), "warplink_cached_domains_test")
    }
}
