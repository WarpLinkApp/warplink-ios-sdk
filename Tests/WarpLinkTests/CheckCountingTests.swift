import XCTest
@testable import WarpLink

/// A check counts as failed when its request is sent. A process that ends while
/// the request is out leaves the failure behind, a 200 that closes the gate
/// clears it, and a check that `configure()` or `clearAttribution()` abandons
/// does not leave one.
final class CheckCountingTests: CheckTrafficTestCase {

    private func holdMatchRequests() -> CancellingTransport {
        let held = CancellingTransport(holdingPathContaining: "/attribution/match")
        SDKEnvironment.makeTransport = { held }
        SDKEnvironment.deliver = { $0() }
        SDKEnvironment.schedule = { _, work in work() }
        return held
    }

    private func startHeldCheck(key: String? = nil) {
        WarpLink.configure(apiKey: key ?? liveKey, options: TestSupport.noAuto)
        WarpLink.fingerprintCollector = FingerprintCollector(vendorIdentifier: { [deviceId] in deviceId })
        WarpLink.checkDeferredDeepLink { _ in }
    }

    private func attemptNumbers(_ transport: InlineTransport) -> [Int] {
        matchBodies(transport).compactMap { $0["attempt_number"] as? Int }
    }

    // conformance: WL-S65

    func testTheRequestCountsAsFailedTheMomentItIsSent() {
        let held = holdMatchRequests()

        startHeldCheck()

        XCTAssertEqual(held.held.count, 1)
        XCTAssertEqual(storage.checkBackoff?.failures, 1)
        XCTAssertEqual(storage.checkBackoff?.lastFailureAt, clock)
    }

    // conformance: WL-S65

    func testAProcessKilledAfterSendingWaitsFifteenMinutesOnTheNextLaunch() {
        _ = holdMatchRequests()
        startHeldCheck()
        relaunch()

        let transport = serving(CheckWire.noMatch)
        configure(transport)
        clock.addTimeInterval(899)
        assertNoMatch(check())
        XCTAssertEqual(matchCount(transport), 0, "the dead check still counts, so nothing is sent")

        clock.addTimeInterval(1)
        check()
        XCTAssertEqual(attemptNumbers(transport), [2], "the second launch that sent a request")
        XCTAssertTrue(storage.isAttributionComplete)
        XCTAssertNil(storage.checkBackoff)
    }

    // conformance: WL-S67

    func testAnAnswerThatClosesTheGateClearsTheCount() {
        let transport = serving(CheckWire.matched)
        configure(transport)

        check()

        XCTAssertTrue(storage.isAttributionComplete)
        XCTAssertNil(storage.checkBackoff)
    }

    func testAnAbandonedCheckGivesBackOnlyItsOwnCount() {
        let failing = serving { _ in CheckWire.offline }
        configure(failing)
        check()
        let afterFirst = storage.checkBackoff
        XCTAssertEqual(afterFirst?.failures, 1)

        relaunch()
        _ = holdMatchRequests()
        clock.addTimeInterval(900)
        startHeldCheck()
        XCTAssertEqual(storage.checkBackoff?.failures, 2)
        WarpLink.configure(
            apiKey: liveKey, options: WarpLinkOptions(debugLogging: true, autoDeferredCheck: false)
        )

        XCTAssertEqual(storage.checkBackoff, afterFirst, "the earlier failure stays, the abandoned one goes")
    }

    // conformance: WL-S72

    func testAnAbandonedCheckGivesBackItsAttemptNumber() {
        let failing = serving { _ in CheckWire.offline }
        configure(failing)
        check()
        XCTAssertEqual(storage.attemptNumber, 1)

        relaunch()
        _ = holdMatchRequests()
        clock.addTimeInterval(900)
        startHeldCheck()
        XCTAssertEqual(storage.attemptNumber, 2, "the held check took the next number")
        WarpLink.configure(
            apiKey: liveKey, options: WarpLinkOptions(debugLogging: true, autoDeferredCheck: false)
        )

        XCTAssertEqual(storage.attemptNumber, 1, "the abandoned check gives its number back")
    }

    func testClearingAttributionWhileACheckIsOutLeavesNoCount() {
        let failing = serving { _ in CheckWire.offline }
        configure(failing, key: testKey)
        check()
        relaunch()
        _ = holdMatchRequests()
        startHeldCheck(key: testKey)
        XCTAssertEqual(storage.checkBackoff?.failures, 2)

        WarpLink.clearAttribution()

        XCTAssertNil(storage.checkBackoff, "the clear wipes the count, and the abandoned check does not bring it back")
    }

    func testACheckSkippedForAgeCountsNothing() {
        installedAt = clock.addingTimeInterval(-40 * day)
        let transport = serving(CheckWire.matched)
        configure(transport)

        check()

        XCTAssertNil(storage.checkBackoff)
        XCTAssertEqual(storage.attemptNumber, 0)
    }
}
