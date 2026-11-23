import XCTest
@testable import WarpLink

/// A pending reply keeps its record and its attempts, a newer paste wins the
/// wait, and a foreground starts the check again.
final class TetherPendingRetryTests: TetherTestCase {

    private let matchPath = "/attribution/match"
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    /// The wall clock is the test's, so a wait for a failed check can pass.
    private func controlClock() {
        SDKEnvironment.now = { [unowned self] in clock }
    }

    private func activate() {
        NotificationCenter.default.post(name: PendingForegroundRetry.notificationName, object: nil)
    }

    private func pendingBody() -> [String: Any] {
        ["matched": false, "tether": ["status": "pending", "accepted": false, "retry_after_seconds": 2]]
    }

    func testANewerPasteDuringTheWaitReplacesTheOldRetry() {
        let newer = "wl1_" + ReferralTokenFixture.token(expiresAt: 1_900_000_001)
        var calls = 0
        let t = transport { request in
            calls += 1
            let body = calls == 1 ? self.pendingBody() : TetherWire.matched(tether: TetherWire.accepted)
            return ReferralWire.answer(200, body, for: request)
        }
        configure(t, mode: .pasteButton)
        SDKEnvironment.schedule = { _, work in
            if let newCode = TetherCode.parse(newer) {
                ReferralServices.pendingStore.save(
                    PendingRedemption(token: newCode.wireText, expiresAt: Date(timeIntervalSince1970: 1_900_000_001))
                )
            }
            work()
        }

        _ = paste(liveCode)

        let sent = t.bodies(forPathContaining: matchPath).compactMap { $0["tether_code"] as? String }
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent.first, liveCode)
        XCTAssertEqual(sent.last, TetherCode.parse(newer)?.wireText, "the old code is not sent again")
    }

    func testRepeatedLaunchesWithPendingRepliesKeepTheRecord() {
        let t = answering(pendingBody())
        configure(t, mode: .pasteButton)
        let recorder = ScheduleRecorder()
        recorder.install()

        _ = paste(liveCode)
        for _ in 0..<(PendingRedemption.maxAttempts + 2) {
            WarpLink.resumePendingInvitation()
        }

        let record = ReferralServices.pendingStore.load()
        XCTAssertNotNil(record, "pending replies never spend the five attempts")
        XCTAssertTrue(record?.hasAttemptsLeft ?? false)
    }

    func testTheAppBecomingActiveRunsTheCheckAgainOnce() {
        clipboard.copy(liveCode)
        var calls = 0
        let t = transport { request in
            calls += 1
            let body = calls <= 2 ? self.pendingBody() : TetherWire.matched(tether: TetherWire.accepted)
            return ReferralWire.answer(200, body, for: request)
        }
        configure(t, mode: .automatic)
        ScheduleRecorder().install()
        controlClock()

        _ = firstOpen()
        XCTAssertEqual(t.bodies(forPathContaining: matchPath).count, 2)
        XCTAssertFalse(WarpLink.isAttributionComplete)

        clock.addTimeInterval(900)
        activate()
        XCTAssertEqual(t.bodies(forPathContaining: matchPath).count, 3)
        XCTAssertTrue(WarpLink.isAttributionComplete)

        activate()
        XCTAssertEqual(t.bodies(forPathContaining: matchPath).count, 3, "only once")
    }

    func testAForegroundInsideTheWaitKeepsTheRecheckForWhenItIsAllowed() {
        clipboard.copy(liveCode)
        var calls = 0
        let t = transport { request in
            calls += 1
            let body = calls <= 2 ? self.pendingBody() : TetherWire.matched(tether: TetherWire.accepted)
            return ReferralWire.answer(200, body, for: request)
        }
        configure(t, mode: .automatic)
        ScheduleRecorder().install()
        controlClock()
        _ = firstOpen()

        clock.addTimeInterval(899)
        activate()
        XCTAssertEqual(t.bodies(forPathContaining: matchPath).count, 2, "inside the wait nothing is sent")

        clock.addTimeInterval(1)
        activate()
        XCTAssertEqual(t.bodies(forPathContaining: matchPath).count, 3, "the recheck was not spent")
        XCTAssertTrue(WarpLink.isAttributionComplete)
    }

    func testAForegroundDuringARunningCheckStaysArmedForTheNext() {
        clipboard.copy(liveCode)
        let t = answering(pendingBody())
        configure(t, mode: .automatic)
        ScheduleRecorder().install()
        controlClock()
        _ = firstOpen()
        clock.addTimeInterval(900)
        let before = t.bodies(forPathContaining: matchPath).count

        WarpLink.lock.lock(); WarpLink.deferredCheckInFlight = true; WarpLink.lock.unlock()
        activate()
        XCTAssertEqual(t.bodies(forPathContaining: matchPath).count, before, "no second check while one runs")

        WarpLink.lock.lock(); WarpLink.deferredCheckInFlight = false; WarpLink.lock.unlock()
        activate()
        XCTAssertGreaterThan(t.bodies(forPathContaining: matchPath).count, before)
    }
}
