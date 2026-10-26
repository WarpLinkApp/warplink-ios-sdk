import XCTest
@testable import WarpLink

final class ReferralRedeemTests: ReferralTestCase {

    private let matchPath = "/attribution/match"

    private func matching() -> InlineTransport {
        transport { ReferralWire.answer(200, ReferralWire.matched, for: $0) }
    }

    // conformance: WL-S41
    func testTextThatIsNotAnInvitationSendsNothingAndConfirmsNothing() {
        let t = matching()
        configure(t)

        let result = redeem("my cat's name is Pepper")

        guard case .success(nil)? = result else { return XCTFail("got \(String(describing: result))") }
        XCTAssertEqual(t.requestCount(forPathContaining: matchPath), 0)
        XCTAssertNil(pending.record)
    }

    // conformance: WL-S42
    func testAnExpiredInvitationIsRefusedLocallyWithTheReopenMessage() {
        let t = matching()
        configure(t)
        now = Date(timeIntervalSince1970: 1_950_000_000)

        let result = redeem(liveToken)

        guard case let .failure(error)? = result else {
            return XCTFail("got \(String(describing: result))")
        }
        assertIsRefusal(error, ReferralMessages.Refusal.expired)
        XCTAssertEqual(t.requestCount(forPathContaining: matchPath), 0)
    }

    // conformance: WL-S42
    func testTheServerRefusingTheTokenSurfacesTheReopenMessage() {
        let t = transport { ReferralWire.refusal("RECOVERY_TOKEN_INVALID", for: $0) }
        configure(t)

        let result = redeem(liveToken)

        guard case let .failure(error)? = result else {
            return XCTFail("got \(String(describing: result))")
        }
        assertIsRefusal(error, ReferralMessages.Refusal.invalid)
        XCTAssertNil(pending.record, "a refused token is not kept for a retry")
        XCTAssertEqual(t.requestCount(forPathContaining: matchPath), 1, "a refusal is not retried")
    }

    func testARefusalIsReadFromTheServerCodeNotFromTheWordsOfTheMessage() {
        let echoed = ReferralMessages.Refusal.invalid.message
        configure(transport {
            ReferralWire.answer(400, ["error": ["code": "BAD_REQUEST", "message": echoed]], for: $0)
        })

        let result = redeem(liveToken)

        guard case let .failure(.serverError(status, message))? = result else {
            return XCTFail("got \(String(describing: result))")
        }
        XCTAssertEqual(status, 400)
        XCTAssertEqual(message, echoed)
        XCTAssertEqual(pending.record?.token, liveToken, "a 400 with another code is not a refusal")
    }

    // conformance: WL-S42
    func testTheServerRefusingAnUnusableLinkDoesNotSayTheInvitationExpired() {
        let t = transport { ReferralWire.refusal("RECOVERY_TOKEN_EXPIRED", for: $0) }
        configure(t)

        let result = redeem(liveToken)

        guard case let .failure(error)? = result else {
            return XCTFail("got \(String(describing: result))")
        }
        assertIsRefusal(error, ReferralMessages.Refusal.unusable)
        XCTAssertFalse(
            ReferralMessages.Refusal.unusable.message.lowercased().contains("expired"),
            "the link may be paused or ended"
        )
        XCTAssertNil(pending.record)
    }

    func testTheRequestCarriesTheDeviceIdSoTheServerCanRecogniseTheSameInstall() throws {
        let t = matching()
        configure(t)
        WarpLink.fingerprintCollector = FingerprintCollector(vendorIdentifier: { "idfv-1" })

        _ = redeem(liveToken)

        let body = try XCTUnwrap(t.lastBody(forPathContaining: matchPath))
        XCTAssertEqual(body["device_id"] as? String, "idfv-1")
        XCTAssertEqual(body["recovery_token"] as? String, liveToken)
    }

    func testTheRequestLeavesTheDeviceIdOutWhenThePlatformHasNone() throws {
        let t = matching()
        configure(t)
        WarpLink.fingerprintCollector = FingerprintCollector(vendorIdentifier: { nil })

        _ = redeem(liveToken)

        let body = try XCTUnwrap(t.lastBody(forPathContaining: matchPath))
        XCTAssertNil(body["device_id"])
    }

    func testTheRequestCarriesTheTokenAndNoSignalThatCouldMatchInstead() throws {
        let t = matching()
        configure(t)

        _ = redeem("  \(liveToken)\n")

        let body = try XCTUnwrap(t.lastBody(forPathContaining: matchPath))
        XCTAssertEqual(body["recovery_token"] as? String, liveToken)
        XCTAssertEqual(body["platform"] as? String, "ios")
        XCTAssertNotNil(body["fingerprint_version"])
        for signal in ["referrer", "timezone", "accept_language", "fingerprint"] {
            XCTAssertNil(body[signal], "\(signal) would let the server skip the token")
        }
    }

    // conformance: WL-S43
    func testAMatchCarriesTheEvidenceFieldsAndIsCached() throws {
        configure(matching())

        let result = redeem(liveToken)

        guard case let .success(link?)? = result else { return XCTFail("got \(String(describing: result))") }
        XCTAssertEqual(link.attributionId, "attr-1")
        XCTAssertEqual(link.matchMethod, .installToken)
        XCTAssertEqual(link.evidenceClass, .exact)
        XCTAssertEqual(link.replayState, .original)
        XCTAssertEqual(link.capturedParams["utm_source"], .string("friend"))
        XCTAssertEqual(link.tappedAt, "2026-10-20T10:00:00.000Z")
        XCTAssertEqual(WarpLink.attributionResult?.linkId, "link-1")
        XCTAssertNil(pending.record)
    }

    func testAnInvitationThatMatchesNothingConfirmsNothing() {
        configure(transport { ReferralWire.answer(200, ["matched": false], for: $0) })

        let result = redeem(liveToken)

        guard case .success(nil)? = result else { return XCTFail("got \(String(describing: result))") }
        XCTAssertNil(WarpLink.attributionResult)
        XCTAssertNil(pending.record)
    }

    func testRedeemingBeforeConfigureFailsAsNotConfigured() {
        guard case .failure(.notConfigured)? = redeem(liveToken) else {
            return XCTFail("expected notConfigured")
        }
    }

    func testARedeemAlreadyRunningSendsNoSecondRequest() {
        let t = matching()
        configure(t)
        XCTAssertTrue(ReferralServices.beginRedeem())

        _ = redeem(liveToken)

        XCTAssertEqual(t.requestCount(forPathContaining: matchPath), 0)
    }

    func testRedeemWorksWhenNoOnLinkSinkIsSet() {
        configure(matching())
        guard case .success(_?)? = redeem(liveToken) else { return XCTFail("expected a match") }
    }
}
