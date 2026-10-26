import XCTest
@testable import WarpLink

final class ReferralClaimTests: ReferralTestCase {

    private let claimPath = "/referrals/claims"
    private let installId = "6f1c1f0e-5a0e-4f3e-9d5b-0a1f1d3c9b11"

    private func claim(_ installer: String = "user-42") -> Result<ReferralClaimResult, WarpLinkError>? {
        var captured: Result<ReferralClaimResult, WarpLinkError>?
        WarpLink.claimReferral(installerId: installer) { captured = $0 }
        return captured
    }

    private func claiming(_ body: [String: Any]) -> InlineTransport {
        transport { ReferralWire.answer(200, body, for: $0) }
    }

    func testAnInstallerIdTheServerWouldRefuseFailsLocallyWithoutARequest() {
        let t = claiming(["status": "none"])
        configure(t)

        for installer in ["", String(repeating: "a", count: 129)] {
            guard case .failure(.serverError(400, _))? = claim(installer) else {
                return XCTFail("expected a local 400 for \(installer.count) characters")
            }
        }
        XCTAssertEqual(t.requestCount(forPathContaining: "/referrals/"), 0)
    }

    // conformance: WL-S45
    func testNoReferralIsTheNoneStatusWithNoError() {
        configure(claiming(["status": "none"]))

        guard case let .success(result)? = claim() else { return XCTFail("none must not be an error") }

        XCTAssertEqual(result.status, .none)
        XCTAssertNil(result.referralId)
        XCTAssertFalse(result.isExact)
    }

    // conformance: WL-S45
    func testAClaimedReferralCarriesItsEvidence() {
        configure(claiming([
            "status": "claimed", "referral_id": "ref-1",
            "link": ["id": "link-1", "slug": "abc", "url": "https://acme.aplnk.to/abc"],
            "match": ["method": "install_token", "exact": true, "confidence": 1.0],
            "flags": [], "updated": false, "replay_state": "original",
        ]))

        guard case let .success(result)? = claim() else { return XCTFail("expected a result") }

        XCTAssertEqual(result.status, .claimed)
        XCTAssertEqual(result.referralId, "ref-1")
        XCTAssertEqual(result.linkId, "link-1")
        XCTAssertEqual(result.linkUrl, "https://acme.aplnk.to/abc")
        XCTAssertEqual(result.matchMethod, .installToken)
        XCTAssertTrue(result.isExact)
        XCTAssertEqual(result.replayState, .original)
    }

    func testFlaggedAndIgnoredStatusesKeepTheirReasons() {
        configure(claiming([
            "status": "flagged", "flags": ["outside_window"], "duplicate_of": "ref-0", "updated": true,
        ]))

        guard case let .success(result)? = claim() else { return XCTFail("expected a result") }

        XCTAssertEqual(result.status, .flagged)
        XCTAssertEqual(result.flags, ["outside_window"])
        XCTAssertEqual(result.duplicateOf, "ref-0")
        XCTAssertTrue(result.updated)
    }

    func testAnUnreadableAnswerIsNoneRatherThanAFailure() {
        configure(claiming(["status": "something-new"]))

        guard case let .success(result)? = claim() else { return XCTFail("expected a result") }

        XCTAssertEqual(result.status, .none)
    }

    // conformance: WL-S45
    func testTheClaimNamesTheInstallerAndWhatTheMatchLeftBehind() throws {
        let t = transport { request in
            let path = request.url?.path ?? ""
            if path.contains("/attribution/match") {
                return ReferralWire.answer(200, ReferralWire.matched, for: request)
            }
            return ReferralWire.answer(200, ["status": "claimed"], for: request)
        }
        configure(t)
        _ = redeem(liveToken)

        _ = claim("user-42")

        let body = try XCTUnwrap(t.lastBody(forPathContaining: claimPath))
        XCTAssertEqual(body["installer_id"] as? String, "user-42")
        XCTAssertEqual(body["install_id"] as? String, installId)
        XCTAssertEqual(body["recovery_token"] as? String, liveToken)
        XCTAssertEqual(body["platform"] as? String, "ios")
    }

    func testTheTokenAReferralLinkOpenHandedOutRidesOnTheClaim() throws {
        let t = InlineTransport { request in
            let path = request.url?.path ?? ""
            if path.contains("/links/resolve/") {
                return ReferralWire.answer(200, [
                    "id": "550e8400-e29b-41d4-a716-446655440000", "slug": "abc123",
                    "domain": "aplnk.to", "destination_url": "https://example.com",
                    "created_at": "2026-01-01T00:00:00.000Z", "recovery_token": self.liveToken,
                ], for: request)
            }
            if path.contains("/referrals/") {
                return ReferralWire.answer(200, ["status": "none"], for: request)
            }
            return ReferralWire.answer(200, ["valid": true, "domains": ["aplnk.to"]], for: request)
        }
        configure(t) { _ in }
        XCTAssertTrue(WarpLink.open(URL(string: "https://aplnk.to/abc123")!))

        _ = claim()

        let body = try XCTUnwrap(t.lastBody(forPathContaining: claimPath))
        XCTAssertEqual(body["recovery_token"] as? String, liveToken)
    }

    func testAnExpiredTokenIsLeftOutOfTheClaim() throws {
        let t = claiming(["status": "none"])
        configure(t)
        ReferralServices.evidenceStore.remember(token: liveToken, expiresAt: now.addingTimeInterval(-1))

        _ = claim()

        let body = try XCTUnwrap(t.lastBody(forPathContaining: claimPath))
        XCTAssertNil(body["recovery_token"])
    }

    func testAnInstallIdThatIsNotAUUIDIsLeftOutOfTheClaim() throws {
        let t = claiming(["status": "none"])
        configure(t)
        ReferralServices.evidenceStore.remember(installId: "not-a-uuid")

        _ = claim()

        let body = try XCTUnwrap(t.lastBody(forPathContaining: claimPath))
        XCTAssertNil(body["install_id"])
    }

    func testARefusedTokenOnAClaimIsNoneNotAnError() {
        configure(transport { ReferralWire.refusal("RECOVERY_TOKEN_EXPIRED", for: $0) })

        guard case let .success(result)? = claim() else { return XCTFail("expected none") }

        XCTAssertEqual(result.status, .none)
    }

    func testARefusedTokenIsNotSentAgainButTheInstallStaysNamed() throws {
        let t = transport { ReferralWire.refusal("RECOVERY_TOKEN_EXPIRED", for: $0) }
        configure(t)
        ReferralServices.evidenceStore.remember(installId: installId)
        ReferralServices.evidenceStore.remember(token: liveToken, expiresAt: nil)

        _ = claim()
        _ = claim()

        let first = try XCTUnwrap(t.bodies(forPathContaining: claimPath).first)
        let second = try XCTUnwrap(t.lastBody(forPathContaining: claimPath))
        XCTAssertEqual(first["recovery_token"] as? String, liveToken)
        XCTAssertNil(second["recovery_token"], "a refused token must not ride on the next claim")
        XCTAssertEqual(second["install_id"] as? String, installId)
    }

    func testAClaimThatIsNotRefusedKeepsTheToken() {
        configure(claiming(["status": "none"]))
        ReferralServices.evidenceStore.remember(token: liveToken, expiresAt: nil)

        _ = claim()

        XCTAssertEqual(ReferralServices.evidenceStore.evidence.recoveryToken, liveToken)
    }

    func testANewerTokenSurvivesTheRefusalOfAnOlderOne() {
        let store = ReferralServices.evidenceStore
        store.remember(token: "newer", expiresAt: nil)

        store.clearToken(ifHolding: "older")

        XCTAssertEqual(store.evidence.recoveryToken, "newer")
    }

    func testAKeyScopeRefusalIsAFailureWithTheServerMessage() {
        configure(transport {
            ReferralWire.answer(403, ["error": ["code": "KEY_APP_MISMATCH", "message": "wrong app"]], for: $0)
        })

        guard case let .failure(.serverError(status, message))? = claim() else {
            return XCTFail("expected a failure")
        }

        XCTAssertEqual(status, 403)
        XCTAssertEqual(message, "wrong app")
    }

    func testClaimingBeforeConfigureFailsAsNotConfigured() {
        guard case .failure(.notConfigured)? = claim() else { return XCTFail("expected notConfigured") }
    }
}
