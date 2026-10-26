import XCTest
@testable import WarpLink

/// The bounded on-device retry of a pasted invitation.
final class ReferralRetryTests: ReferralTestCase {

    private let matchPath = "/attribution/match"

    private func offline() -> InlineTransport {
        transport { _ in (nil, nil, URLError(.notConnectedToInternet)) }
    }

    private func matching() -> InlineTransport {
        transport { ReferralWire.answer(200, ReferralWire.matched, for: $0) }
    }

    // conformance: WL-S44
    func testANetworkFailureKeepsTheInvitationForALaterLaunch() {
        configure(offline())

        let result = redeem(liveToken)

        guard case .failure(.networkError)? = result else { return XCTFail("got \(String(describing: result))") }
        let kept = pending.record
        XCTAssertEqual(kept?.token, liveToken)
        XCTAssertEqual(kept?.attempts, 1)
    }

    // conformance: WL-S44
    func testALaterLaunchDeliversTheKeptInvitationOnceAndClearsIt() {
        configure(offline())
        _ = redeem(liveToken)
        let delivered = Results()
        let t = matching()
        // Held back while configuring: configure resumes by itself, and it
        // would do so against the real storage rather than this test's.
        let kept = pending.record
        pending.record = nil
        configure(t) { delivered.append($0) }
        pending.record = kept

        WarpLink.resumePendingInvitation()
        WarpLink.resumePendingInvitation()

        XCTAssertEqual(t.requestCount(forPathContaining: matchPath), 1, "one token, one delivery")
        XCTAssertEqual(delivered.all.count, 1)
        guard case .success(_?)? = delivered.all.first else { return XCTFail("expected a link in onLink") }
        XCTAssertNil(pending.record)
    }

    func testTheRecordIsCountedBeforeTheRequestGoesOut() {
        configure(offline())

        _ = redeem(liveToken)

        XCTAssertEqual(pending.saved.first?.attempts, 1, "a kill mid-request still counts")
    }

    // conformance: WL-S44
    func testARecordWithNoAttemptsLeftIsDroppedAndNothingIsSent() {
        pending.record = PendingRedemption(
            token: liveToken, expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            attempts: PendingRedemption.maxAttempts
        )
        let t = matching()

        configure(t)

        XCTAssertEqual(t.requestCount(forPathContaining: matchPath), 0)
        XCTAssertNil(pending.record, "configure resumes, and resume drops a spent record")
    }

    // conformance: WL-S44
    func testARecordPastItsExpiryIsDroppedAndNothingIsSent() {
        pending.record = PendingRedemption(
            token: liveToken, expiresAt: Date(timeIntervalSince1970: 1_700_000_000), attempts: 1
        )
        let t = matching()

        configure(t)

        XCTAssertEqual(t.requestCount(forPathContaining: matchPath), 0)
        XCTAssertNil(pending.record)
    }

    func testTheFifthFailureLeavesNothingToRetry() {
        configure(offline())
        pending.record = PendingRedemption(
            token: liveToken, expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            attempts: PendingRedemption.maxAttempts - 1
        )
        WarpLink.resumePendingInvitation()

        XCTAssertNil(pending.record, "the last allowed attempt failed, so the record ends")
    }

    func testAResumedRedeemThatTheServerRefusesIsDropped() {
        configure(transport { ReferralWire.refusal("RECOVERY_TOKEN_EXPIRED", for: $0) })
        pending.record = PendingRedemption(
            token: liveToken, expiresAt: Date(timeIntervalSince1970: 1_900_000_000), attempts: 1
        )

        WarpLink.resumePendingInvitation()

        XCTAssertNil(pending.record)
    }

    func testAPendingAnswerKeepsTheInvitationAndTellsTheUserToTryAgain() {
        configure(transport { ReferralWire.pendingAnswer(for: $0) })

        let result = redeem(liveToken)

        guard case let .failure(error)? = result, case let .serverError(status, message) = error else {
            return XCTFail("got \(String(describing: result))")
        }
        XCTAssertEqual(status, 503)
        XCTAssertEqual(message, ReferralMessages.pendingInvitation)
        XCTAssertEqual(pending.record?.token, liveToken, "a pending answer is retried, not dropped")
        XCTAssertEqual(pending.record?.attempts, 1)
    }

    func testAResumedRedeemThatTheServerAnswersPendingKeepsTheRecord() {
        configure(transport { ReferralWire.pendingAnswer(for: $0) })
        pending.record = PendingRedemption(
            token: liveToken, expiresAt: Date(timeIntervalSince1970: 1_900_000_000), attempts: 1
        )

        WarpLink.resumePendingInvitation()

        XCTAssertEqual(pending.record?.token, liveToken)
        XCTAssertEqual(pending.record?.attempts, 2)
    }

    func testNothingIsResumedWhenNothingWasKept() {
        let t = matching()
        configure(t)

        WarpLink.resumePendingInvitation()

        XCTAssertEqual(t.requestCount(forPathContaining: matchPath), 0)
    }
}
