import XCTest
@testable import WarpLink

/// A redeem and the automatic deferred check run side by side at launch. The
/// exact answer of the invitation must win, whichever answers first.
final class ReferralDeferredRaceTests: ReferralTestCase {

    private let probabilistic: [String: Any] = [
        "matched": true,
        "match_type": "probabilistic",
        "match_confidence": 0.7,
        "link_id": "link-weak",
        "destination_url": "https://example.com/other",
        "install_id": "00000000-0000-4000-8000-000000000001",
    ]

    /// Holds the deferred check (no recovery token) and answers the redeem.
    private func raceTransport() -> GatedTransport {
        GatedTransport(
            holding: { request in
                let isMatch = request.url?.path.contains("/attribution/match") == true
                let body = String(data: request.resolvedHTTPBody ?? Data(), encoding: .utf8) ?? ""
                return isMatch && !body.contains("recovery_token")
            },
            otherwise: { request in
                let path = request.url?.path ?? ""
                if path.contains("/attribution/match") {
                    return ReferralWire.answer(200, ReferralWire.matched, for: request)
                }
                return ReferralWire.answer(200, ["valid": true, "domains": ["aplnk.to"]], for: request)
            }
        )
    }

    /// Launch with a kept invitation: the deferred check starts, then the resume,
    /// in the order `configure()` starts them.
    private func launchWithKeptInvitation(_ gate: GatedTransport, onLink: Results) {
        configure(gate) { onLink.append($0) }
        pending.record = PendingRedemption(
            token: liveToken, expiresAt: Date(timeIntervalSince1970: 1_900_000_000), attempts: 1
        )
        WarpLink.runAutoDeferredCheck()
        WarpLink.resumePendingInvitation()
    }

    func testALateEstimateAfterTheExactRedeemIsNotRoutedAndKeepsTheCache() {
        let gate = raceTransport()
        let onLink = Results()

        launchWithKeptInvitation(gate, onLink: onLink)
        XCTAssertEqual(gate.held.count, 1, "the deferred check is still open")
        gate.release(status: 200, body: probabilistic)

        XCTAssertEqual(onLink.all.count, 1, "one referral, one onLink")
        XCTAssertEqual(WarpLink.attributionResult?.linkId, "link-1")
        XCTAssertEqual(WarpLink.attributionResult?.evidenceClass, .exact)
        XCTAssertEqual(
            ReferralServices.evidenceStore.evidence.installId,
            ReferralWire.matched["install_id"] as? String,
            "the superseded check leaves the install id alone"
        )
    }

    func testALateNoMatchAfterTheExactRedeemKeepsTheCache() {
        let gate = raceTransport()
        let onLink = Results()

        launchWithKeptInvitation(gate, onLink: onLink)
        gate.release(status: 200, body: ["matched": false])

        XCTAssertEqual(onLink.all.count, 1)
        XCTAssertEqual(WarpLink.attributionResult?.linkId, "link-1", "a no-match must not blank the cache")
    }

    func testTheRedeemStopsTheDeferredCheckRequest() {
        let gate = raceTransport()

        launchWithKeptInvitation(gate, onLink: Results())

        XCTAssertTrue(gate.held[0].cancelled)
    }

    func testTheExactRedeemAnsweringAfterTheEstimateWins() {
        let gate = GatedTransport(
            holding: { request in
                let body = String(data: request.resolvedHTTPBody ?? Data(), encoding: .utf8) ?? ""
                return body.contains("recovery_token")
            },
            otherwise: { request in
                let path = request.url?.path ?? ""
                if path.contains("/attribution/match") {
                    return ReferralWire.answer(200, self.probabilistic, for: request)
                }
                return ReferralWire.answer(200, ["valid": true, "domains": ["aplnk.to"]], for: request)
            }
        )

        launchWithKeptInvitation(gate, onLink: Results())
        XCTAssertEqual(WarpLink.attributionResult?.linkId, "link-weak")
        gate.release(status: 200, body: ReferralWire.matched)

        XCTAssertEqual(WarpLink.attributionResult?.linkId, "link-1")
        XCTAssertEqual(WarpLink.attributionResult?.evidenceClass, .exact)
    }
}
