import XCTest
@testable import WarpLink

/// What a launch does with an invitation kept from an earlier one.
final class ReferralResumeTests: ReferralTestCase {

    private let expiry = Date(timeIntervalSince1970: 1_900_000_000)

    private func keep(_ token: String, attempts: Int = 1) {
        pending.record = PendingRedemption(token: token, expiresAt: expiry, attempts: attempts)
    }

    private func holdingRedeems() -> GatedTransport {
        GatedTransport(
            holding: { request in
                let body = String(data: request.resolvedHTTPBody ?? Data(), encoding: .utf8) ?? ""
                return body.contains("recovery_token")
            },
            otherwise: { ReferralWire.answer(200, ["valid": true, "domains": ["aplnk.to"]], for: $0) }
        )
    }

    func testANewPasteDuringAResumeIsKeptNotDropped() {
        let gate = holdingRedeems()
        configure(gate)
        keep(liveToken)
        WarpLink.resumePendingInvitation()
        let newer = ReferralTokenFixture.token(expiresAt: 1_900_000_000, filler: 40)

        let result = redeem(newer)

        guard case .success(nil)? = result else { return XCTFail("got \(String(describing: result))") }
        XCTAssertEqual(pending.record?.token, newer)
        XCTAssertEqual(pending.record?.attempts, 0, "a new paste starts its own count")
    }

    func testTheRunInFlightDoesNotClearTheNewerInvitationWhenItEnds() {
        let gate = holdingRedeems()
        configure(gate)
        keep(liveToken)
        WarpLink.resumePendingInvitation()
        let newer = ReferralTokenFixture.token(expiresAt: 1_900_000_000, filler: 40)
        _ = redeem(newer)

        gate.release(status: 200, body: ReferralWire.matched)

        XCTAssertEqual(pending.record?.token, newer)
    }

    func testAFailedResumeIsNotRoutedToOnLink() {
        let delivered = Results()
        configure(transport { _ in (nil, nil, URLError(.notConnectedToInternet)) }) { delivered.append($0) }
        keep(liveToken)

        WarpLink.resumePendingInvitation()

        XCTAssertTrue(delivered.all.isEmpty)
        XCTAssertEqual(pending.record?.attempts, 2, "the failure still counts and keeps the record")
    }

    func testARefusedResumeIsNotRoutedToOnLink() {
        let delivered = Results()
        configure(transport { ReferralWire.refusal("RECOVERY_TOKEN_INVALID", for: $0) }) { delivered.append($0) }
        keep(liveToken)

        WarpLink.resumePendingInvitation()

        XCTAssertTrue(delivered.all.isEmpty)
        XCTAssertNil(pending.record)
    }
}
