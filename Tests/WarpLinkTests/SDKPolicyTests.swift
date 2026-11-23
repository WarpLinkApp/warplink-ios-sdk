import XCTest
@testable import WarpLink

/// The server's traffic policy: built-in defaults, a server block that replaces
/// them, and the clamps that stop a bad block from silencing or flooding the SDK.
final class SDKPolicyTests: XCTestCase {

    private let day: TimeInterval = 86_400

    // conformance: WL-S69

    func testDefaultsMatchTheContract() {
        let defaults = SDKPolicy.defaults
        XCTAssertEqual(defaults.retryDelays, [900, 3600, 21600, 86400])
        XCTAssertEqual(defaults.giveUpAfter, 259_200)
        XCTAssertEqual(defaults.maxInstallAge, 2_592_000)
        XCTAssertEqual(defaults.rawSignalMaxInstallAge, 172_800)
    }

    func testAServerBlockReplacesTheDefaults() throws {
        let policy = try XCTUnwrap(SDKPolicy.parse([
            "retry_delays_seconds": [120, 600],
            "give_up_after_seconds": 7200,
            "max_install_age_seconds": 10 * day,
            "raw_signal_max_install_age_seconds": 3 * day,
        ] as [String: Any]))
        XCTAssertEqual(policy.retryDelays, [120, 600])
        XCTAssertEqual(policy.giveUpAfter, 7200)
        XCTAssertEqual(policy.maxInstallAge, 10 * day)
        XCTAssertEqual(policy.rawSignalMaxInstallAge, 3 * day)
    }

    // conformance: WL-S69

    func testEveryValueIsClampedToItsRange() throws {
        let low = try XCTUnwrap(SDKPolicy.parse([
            "retry_delays_seconds": [1, 59],
            "give_up_after_seconds": 10,
            "max_install_age_seconds": 100,
            "raw_signal_max_install_age_seconds": 10,
        ] as [String: Any]))
        XCTAssertEqual(low.retryDelays, [60, 60])
        XCTAssertEqual(low.giveUpAfter, 3600)
        XCTAssertEqual(low.maxInstallAge, day)
        XCTAssertEqual(low.rawSignalMaxInstallAge, 3600)

        let high = try XCTUnwrap(SDKPolicy.parse([
            "retry_delays_seconds": [8 * day, 1_000_000_000],
            "give_up_after_seconds": 100 * day,
            "max_install_age_seconds": 1000 * day,
            "raw_signal_max_install_age_seconds": 2000 * day,
        ] as [String: Any]))
        XCTAssertEqual(high.retryDelays, [7 * day, 7 * day])
        XCTAssertEqual(high.giveUpAfter, 30 * day)
        XCTAssertEqual(high.maxInstallAge, 365 * day)
        XCTAssertEqual(high.rawSignalMaxInstallAge, 365 * day, "raw limit never exceeds the install limit")
    }

    // conformance: WL-S69

    func testTheRawLimitFollowsAClampedInstallLimit() throws {
        let policy = try XCTUnwrap(SDKPolicy.parse([
            "max_install_age_seconds": 2 * day,
            "raw_signal_max_install_age_seconds": 5 * day,
        ] as [String: Any]))
        XCTAssertEqual(policy.maxInstallAge, 2 * day)
        XCTAssertEqual(policy.rawSignalMaxInstallAge, 2 * day)
    }

    func testAMissingOrNonObjectBlockIsNotAPolicy() {
        XCTAssertNil(SDKPolicy.parse(nil))
        XCTAssertNil(SDKPolicy.parse("nope"))
        XCTAssertNil(SDKPolicy.parse([1, 2, 3]))
    }

    func testABlockWithNoValidFieldIsNotAPolicy() {
        XCTAssertNil(SDKPolicy.parse([:] as [String: Any]))
        XCTAssertNil(SDKPolicy.parse([
            "retry_delays_seconds": "soon",
            "give_up_after_seconds": [1],
            "max_install_age_seconds": Double.nan,
        ] as [String: Any]))
    }

    func testABadFieldKeepsItsDefaultAndTheOthersApply() throws {
        let policy = try XCTUnwrap(SDKPolicy.parse([
            "retry_delays_seconds": "soon",
            "give_up_after_seconds": [1],
            "max_install_age_seconds": 40 * day,
        ] as [String: Any]))
        XCTAssertEqual(policy.retryDelays, SDKPolicy.defaults.retryDelays)
        XCTAssertEqual(policy.giveUpAfter, SDKPolicy.defaults.giveUpAfter)
        XCTAssertEqual(policy.maxInstallAge, 40 * day)
        XCTAssertEqual(policy.rawSignalMaxInstallAge, SDKPolicy.defaults.rawSignalMaxInstallAge)
    }

    func testAnEmptyOrMixedDelayListKeepsTheDefaultList() throws {
        for list in [[] as [Any], [900, "x"] as [Any], [Double.nan] as [Any]] {
            let policy = try XCTUnwrap(SDKPolicy.parse([
                "retry_delays_seconds": list,
                "give_up_after_seconds": 2 * day,
            ] as [String: Any]))
            XCTAssertEqual(policy.retryDelays, SDKPolicy.defaults.retryDelays)
        }
    }

    func testAnOversizedDelayListIsCut() throws {
        let policy = try XCTUnwrap(SDKPolicy.parse(
            ["retry_delays_seconds": Array(repeating: 600, count: 500)] as [String: Any]
        ))
        XCTAssertLessThanOrEqual(policy.retryDelays.count, SDKPolicy.maxDelayCount)
    }

    func testTheDelayForAFailureCountRepeatsTheLastDelay() {
        let policy = SDKPolicy.defaults
        XCTAssertEqual(policy.retryDelay(afterFailures: 1), 900)
        XCTAssertEqual(policy.retryDelay(afterFailures: 2), 3600)
        XCTAssertEqual(policy.retryDelay(afterFailures: 3), 21600)
        XCTAssertEqual(policy.retryDelay(afterFailures: 4), 86400)
        XCTAssertEqual(policy.retryDelay(afterFailures: 9), 86400)
    }

    func testThePolicyRoundTripsThroughItsWireForm() throws {
        let original = try XCTUnwrap(SDKPolicy.parse([
            "retry_delays_seconds": [300, 900],
            "give_up_after_seconds": 86_400,
        ] as [String: Any]))
        let data = try JSONSerialization.data(withJSONObject: original.wire)
        let again = SDKPolicy.parse(try JSONSerialization.jsonObject(with: data))
        XCTAssertEqual(again, original)
    }
}
