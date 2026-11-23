import XCTest
@testable import WarpLink

/// `sdk_policy` on the match and validate answers: stored when valid, clamped,
/// kept when a later answer has none, and used by the next check.
final class SDKPolicyFlowTests: CheckTrafficTestCase {

    private let shortWait: [String: Any] = ["retry_delays_seconds": [120]]

    private func matchBody(policy: Any?) -> [String: Any] {
        var body = CheckWire.noMatch
        if let policy = policy { body["sdk_policy"] = policy }
        return body
    }

    // conformance: WL-S69

    func testAMatchAnswerWithAPolicyIsStored() throws {
        configure(serving(matchBody(policy: shortWait)))

        check()

        XCTAssertEqual(storage.policy.retryDelays, [120])
        XCTAssertEqual(storage.policy.giveUpAfter, SDKPolicy.defaults.giveUpAfter)
    }

    // conformance: WL-S69

    func testAValidateAnswerWithAPolicyIsStored() {
        let transport = InlineTransport { request in
            var body = CheckWire.validated
            body["sdk_policy"] = ["give_up_after_seconds": 7200]
            return CheckWire.answer(body, for: request)
        }

        configure(transport)

        XCTAssertEqual(storage.policy.giveUpAfter, 7200)
    }

    func testAnOldAnswerWithoutAPolicyKeepsTheDefaults() {
        configure(serving(CheckWire.noMatch))

        check()

        XCTAssertEqual(storage.policy, SDKPolicy.defaults)
    }

    func testALaterAnswerWithoutAPolicyKeepsTheStoredOne() {
        let online = Flag()
        let transport = serving { request in
            online.isRaised
                ? CheckWire.answer(CheckWire.matched, for: request)
                : CheckWire.answer(["matched": true, "sdk_policy": self.shortWait], for: request)
        }
        configure(transport)
        check()
        online.raise()
        check()

        XCTAssertEqual(storage.policy.retryDelays, [120])
    }

    // conformance: WL-S69

    func testABadPolicyBlockChangesNothing() {
        configure(serving(matchBody(policy: "unlimited")))

        check()

        XCTAssertEqual(storage.policy, SDKPolicy.defaults)
    }

    func testAStoredPolicyIsClamped() {
        configure(serving(matchBody(policy: [
            "retry_delays_seconds": [1],
            "give_up_after_seconds": 1,
        ] as [String: Any])))

        check()

        XCTAssertEqual(storage.policy.retryDelays, [60])
        XCTAssertEqual(storage.policy.giveUpAfter, 3600)
    }

    func testTheNextFailedCheckWaitsTheServersDelay() {
        let failing = Flag()
        let transport = serving { request in
            failing.isRaised
                ? CheckWire.offline
                : CheckWire.answer(["matched": true, "sdk_policy": self.shortWait], for: request)
        }
        configure(transport)
        check()
        failing.raise()
        check()
        let sent = matchCount(transport)

        clock.addTimeInterval(119)
        check()
        XCTAssertEqual(matchCount(transport), sent, "the server's two minutes have not passed")

        clock.addTimeInterval(1)
        check()
        XCTAssertGreaterThan(matchCount(transport), sent)
    }

    func testThePolicySurvivesAnAppRestart() {
        configure(serving(matchBody(policy: shortWait)))
        check()

        relaunch()
        configure(serving(CheckWire.noMatch))

        XCTAssertEqual(storage.policy.retryDelays, [120])
    }
}
