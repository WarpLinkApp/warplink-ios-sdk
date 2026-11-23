import XCTest
@testable import WarpLink

/// A code the person pasted: what is sent, what is kept, and when the
/// clipboard is emptied.
final class TetherRedeemTests: TetherTestCase {

    private let matchPath = "/attribution/match"

    override func setUp() {
        super.setUp()
        clipboard.copy(liveCode)
    }

    // conformance: WL-S53
    func testAPasteSendsTheCodeWithTheReadModeAndTheInstallation() throws {
        let t = answering(TetherWire.matched(tether: TetherWire.accepted))
        configure(t, mode: .pasteButton)

        _ = paste(liveCode)

        let body = try lastMatchBody(t)
        XCTAssertEqual(body["tether_code"] as? String, liveCode)
        XCTAssertEqual(body["tether_read_mode"] as? String, "paste_button")
        XCTAssertEqual(body["sdk_platform"] as? String, "ios")
        XCTAssertEqual(body["installation_id"] as? String, storage.installationId)
        XCTAssertNil(body["recovery_token"])
        XCTAssertEqual(clipboard.readCount, 0, "the SDK never reads in paste button mode")
    }

    // conformance: WL-S55
    func testAnAcceptedCodeEmptiesTheClipboard() {
        configure(answering(TetherWire.matched(tether: TetherWire.accepted)), mode: .pasteButton)

        let outcome = paste(liveCode)

        guard case .success(let link?)? = outcome?.0 else { return XCTFail("got \(String(describing: outcome))") }
        XCTAssertEqual(link.linkId, "link-1")
        XCTAssertNil(clipboard.text)
        XCTAssertEqual(clipboard.clearCount, 1)
    }

    // conformance: WL-S55
    func testARejectedCodeLeavesTheClipboardAlone() {
        configure(answering(TetherWire.matched(tether: TetherWire.rejected)), mode: .pasteButton)

        _ = paste(liveCode)

        XCTAssertEqual(clipboard.text, liveCode)
        XCTAssertEqual(clipboard.clearCount, 0)
    }

    // conformance: WL-S55
    func testAFailedRequestLeavesTheClipboardAloneAndKeepsTheCode() {
        configure(answering(["error": ["code": "INTERNAL", "message": "x"]], status: 500), mode: .pasteButton)

        let outcome = paste(liveCode)

        guard case .failure? = outcome?.0 else { return XCTFail("got \(String(describing: outcome))") }
        XCTAssertEqual(clipboard.clearCount, 0)
        XCTAssertEqual(pending.record?.token, liveCode, "kept so a later launch can try again")
    }

    // conformance: WL-S55
    func testAClipboardThatChangedDuringTheRequestIsLeftAlone() {
        let t = transport { [unowned self] request in
            clipboard.copy("the person copied this meanwhile")
            return ReferralWire.answer(200, TetherWire.matched(tether: TetherWire.accepted), for: request)
        }
        configure(t, mode: .pasteButton)

        _ = paste(liveCode)

        XCTAssertEqual(clipboard.text, "the person copied this meanwhile")
        XCTAssertEqual(clipboard.clearCount, 0)
    }

    // conformance: WL-S54
    func testTextThatIsNotACodeSendsNothingAndLeavesAMissForTheNextRequest() {
        let t = answering(TetherWire.matched(tether: nil))
        configure(t, mode: .pasteButton)

        let outcome = paste("my cat's name is Pepper")

        guard case .success(nil)? = outcome?.0 else { return XCTFail("got \(String(describing: outcome))") }
        XCTAssertEqual(outcome?.1.miss, .clipboardEmpty)
        XCTAssertEqual(t.requestCount(forPathContaining: matchPath), 0)
        XCTAssertEqual(TetherServices.takeMiss()?.reason, .clipboardEmpty)
    }

    // conformance: WL-S59
    func testAPasteWithNoTextIsAMiss() {
        let t = answering(TetherWire.matched(tether: nil))
        configure(t, mode: .pasteButton)

        let outcome = paste(nil)

        XCTAssertEqual(outcome?.1.miss, .clipboardEmpty)
        XCTAssertEqual(t.requestCount(forPathContaining: matchPath), 0)
    }

    // conformance: WL-S42
    func testAnExpiredLiveCodeIsRefusedWithoutARequest() {
        let t = answering(TetherWire.matched(tether: TetherWire.accepted))
        configure(t, mode: .pasteButton)
        now = Date(timeIntervalSince1970: 1_950_000_000)

        let outcome = paste(liveCode)

        guard case let .failure(error)? = outcome?.0 else { return XCTFail("got \(String(describing: outcome))") }
        assertIsRefusal(error, ReferralMessages.Refusal.expired)
        XCTAssertEqual(t.requestCount(forPathContaining: matchPath), 0)
        XCTAssertEqual(clipboard.clearCount, 0)
    }

    // conformance: WL-S61
    func testATestCodeReturnsAReceiptAndRecordsNothing() {
        let t = answering(TetherWire.matched(tether: TetherWire.test))
        configure(t, mode: .pasteButton)

        let outcome = paste("wl1t_signedbody")

        guard case .success(nil)? = outcome?.0 else { return XCTFail("got \(String(describing: outcome))") }
        XCTAssertEqual(outcome?.1.tether?.testReceipt, "receipt-1")
        XCTAssertEqual(WarpLink.lastTetherTestReceipt, "receipt-1")
        XCTAssertNil(storage.cachedAttribution, "a test records no link")
        XCTAssertTrue(pending.saved.isEmpty, "a test code is never kept for a retry")
        XCTAssertNil(ReferralServices.evidenceStore.evidence.recoveryToken, "a test records no evidence")
    }

    // conformance: WL-S61
    func testATestCodeIsClearedFromTheClipboardAsALiveCodeIs() {
        clipboard.copy("wl1t_signedbody")
        configure(answering(TetherWire.matched(tether: TetherWire.test)), mode: .pasteButton)

        _ = paste("wl1t_signedbody")

        XCTAssertNil(clipboard.text)
    }

    func testAnUnprefixedInvitationStillTravelsAsRecoveryTokenAndClearsNothing() throws {
        let t = answering(ReferralWire.matched)
        configure(t, mode: .pasteButton)

        _ = redeem(liveToken)

        let body = try lastMatchBody(t)
        XCTAssertEqual(body["recovery_token"] as? String, liveToken)
        XCTAssertNil(body["tether_code"])
        XCTAssertEqual(clipboard.clearCount, 0, "the public call has no stamp, so it never clears")
    }

    // conformance: WL-S53
    func testAKeptCodeIsSentAgainInTheConfiguredModeOnTheNextLaunch() throws {
        let t = answering(TetherWire.matched(tether: TetherWire.accepted))
        configure(t, mode: .onCall)
        pending.record = PendingRedemption(
            token: liveCode, expiresAt: Date(timeIntervalSince1970: 1_900_000_000), attempts: 1
        )

        WarpLink.resumePendingInvitation()

        let body = try lastMatchBody(t)
        XCTAssertEqual(body["tether_code"] as? String, liveCode)
        XCTAssertEqual(body["tether_read_mode"] as? String, "on_call")
        XCTAssertEqual(clipboard.clearCount, 0, "a resumed code has no stamp to clear by")
        XCTAssertNil(pending.record)
    }
}
