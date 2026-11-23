import XCTest
@testable import WarpLink

/// The cross-launch backoff on the shared check path: a failed check makes the
/// next ones wait, a 200 clears the wait, and the SDK gives up after three days.
final class CheckBackoffFlowTests: CheckTrafficTestCase {

    /// A transport that fails every match until `online` is set, then serves a no-match.
    private func flaky(online: Flag) -> InlineTransport {
        serving { request in
            online.isRaised ? CheckWire.answer(CheckWire.noMatch, for: request) : CheckWire.offline
        }
    }

    // conformance: WL-S65

    func testAFailedCheckMakesTheNextOneWaitWithoutARequest() {
        let online = Flag()
        let transport = flaky(online: online)
        configure(transport)

        guard case .failure? = check() else { return XCTFail("the first check fails") }
        XCTAssertEqual(matchCount(transport), 3, "one launch, three in-launch attempts")

        online.raise()
        clock.addTimeInterval(899)
        assertNoMatch(check())
        XCTAssertEqual(matchCount(transport), 3, "inside the wait nothing is sent")
        XCTAssertFalse(storage.isAttributionComplete)
    }

    func testTheNextCheckRunsOnceTheWaitHasPassed() {
        let online = Flag()
        let transport = flaky(online: online)
        configure(transport)
        check()

        online.raise()
        clock.addTimeInterval(900)
        assertNoMatch(check())

        XCTAssertEqual(matchCount(transport), 4)
        XCTAssertTrue(storage.isAttributionComplete)
    }

    func testThreeInLaunchAttemptsCountAsOneFailure() throws {
        let transport = flaky(online: Flag())
        configure(transport)

        check()

        XCTAssertEqual(storage.checkBackoff?.failures, 1)
        XCTAssertEqual(storage.checkBackoff?.firstFailureAt.timeIntervalSince1970, clock.timeIntervalSince1970)
    }

    // conformance: WL-S65

    func testEachFailedLaunchWaitsLonger() {
        let transport = flaky(online: Flag())
        configure(transport)
        let waits: [TimeInterval] = [900, 3600, 21_600, 86_400, 86_400]

        for (index, wait) in waits.enumerated() {
            check()
            let sent = matchCount(transport)
            clock.addTimeInterval(wait - 1)
            check()
            XCTAssertEqual(matchCount(transport), sent, "inside wait \(index + 1)")
            clock.addTimeInterval(1)
        }
        XCTAssertEqual(storage.checkBackoff?.failures, 5)
    }

    // conformance: WL-S67

    func testASuccessfulAnswerClearsTheBackoff() {
        let online = Flag()
        let transport = flaky(online: online)
        configure(transport)
        check()
        XCTAssertNotNil(storage.checkBackoff)

        online.raise()
        clock.addTimeInterval(900)
        check()

        XCTAssertNil(storage.checkBackoff)
    }

    // conformance: WL-S66

    func testTheSdkStopsAskingThreeDaysAfterTheFirstFailure() {
        let online = Flag()
        let transport = flaky(online: online)
        configure(transport)
        check()
        let sent = matchCount(transport)

        online.raise()
        clock.addTimeInterval(3 * day)
        assertNoMatch(check())
        clock.addTimeInterval(30 * day)
        assertNoMatch(check())

        XCTAssertEqual(matchCount(transport), sent, "after the give-up time no request is sent")
        XCTAssertFalse(storage.isAttributionComplete)
    }

    // conformance: WL-S66

    func testATestKeyIgnoresTheWaitAndTheGiveUp() {
        let online = Flag()
        let transport = flaky(online: online)
        configure(transport, key: testKey)
        check()
        clock.addTimeInterval(10 * day)
        check()

        XCTAssertEqual(matchCount(transport), 6, "both checks sent all three attempts")
    }

    // conformance: WL-S67

    func testAnAnswerThatDoesNotCloseTheGateStaysCounted() {
        let transport = serving(["matched": true])
        configure(transport)

        check()

        XCTAssertEqual(storage.checkBackoff?.failures, 1, "a 200 that closes nothing is still a failed check")
        XCTAssertFalse(storage.isAttributionComplete)
    }

    func testARepeatedAnswerWithNothingToRouteWaitsAndGivesUp() {
        let transport = serving(["matched": true])
        configure(transport)
        check()

        relaunch()
        configure(transport)
        clock.addTimeInterval(60)
        assertNoMatch(check())
        XCTAssertEqual(matchCount(transport), 1, "the second launch sends nothing inside the wait")

        clock.addTimeInterval(3 * day)
        check()
        XCTAssertEqual(matchCount(transport), 1, "after the give-up time nothing is sent")
    }

    func testARefusedKeyCountsAsAFailedCheck() {
        let transport = serving([:], status: 401)
        configure(transport)

        check()

        XCTAssertEqual(storage.checkBackoff?.failures, 1)
        XCTAssertEqual(matchCount(transport), 1)
    }

    func testAnAbandonedCheckGivesItsCountBack() {
        let held = CancellingTransport(holdingPathContaining: "/attribution/match")
        SDKEnvironment.makeTransport = { held }
        SDKEnvironment.deliver = { $0() }
        SDKEnvironment.schedule = { _, work in work() }
        WarpLink.configure(apiKey: liveKey, options: TestSupport.noAuto)
        WarpLink.fingerprintCollector = FingerprintCollector(vendorIdentifier: { [deviceId] in deviceId })

        WarpLink.checkDeferredDeepLink { _ in }
        XCTAssertEqual(held.held.count, 1)
        WarpLink.configure(
            apiKey: liveKey, options: WarpLinkOptions(debugLogging: true, autoDeferredCheck: false)
        )

        XCTAssertNil(storage.checkBackoff, "cancelling for a reconfigure is not a network failure")
    }

    func testClearingAttributionClearsTheBackoff() {
        let transport = flaky(online: Flag())
        configure(transport, key: testKey)
        check()
        XCTAssertNotNil(storage.checkBackoff)

        storage.clearAttribution()

        XCTAssertNil(storage.checkBackoff)
        XCTAssertEqual(storage.attemptNumber, 0)
    }
}
