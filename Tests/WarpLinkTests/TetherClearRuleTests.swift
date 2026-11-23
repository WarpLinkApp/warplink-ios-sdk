import XCTest
@testable import WarpLink

/// What the server's answer must say before the clipboard is emptied, and which
/// text the SDK takes from it at all.
final class TetherClearRuleTests: TetherTestCase {

    // conformance: WL-S55
    func testAnAcceptedAutomaticCodeEmptiesTheClipboard() {
        clipboard.copy(liveCode)
        configure(answering(TetherWire.matched(tether: TetherWire.accepted)), mode: .automatic)

        _ = firstOpen()

        XCTAssertNil(clipboard.text)
    }

    // conformance: WL-S54
    func testAnUnprefixedTokenOnTheClipboardIsNeverSentByAnAutomaticRead() throws {
        clipboard.copy(liveToken)
        let t = answering(ReferralWire.matched)
        configure(t, mode: .automatic)

        _ = firstOpen()

        let body = try lastMatchBody(t)
        XCTAssertNil(body["recovery_token"])
        XCTAssertNil(body["tether_code"])
        XCTAssertEqual(body["tether_miss_reason"] as? String, "clipboard_empty")
        XCTAssertEqual(clipboard.clearCount, 0)
    }

    // conformance: WL-S61
    func testALiveCodeTheServerCalledATestIsNotClearedByAnAutomaticRead() {
        clipboard.copy(liveCode)
        configure(answering(TetherWire.matched(tether: TetherWire.test)), mode: .automatic)

        _ = firstOpen()

        XCTAssertEqual(clipboard.text, liveCode)
    }

    // conformance: WL-S55
    func testATestCodeTheServerAcceptedAsLiveIsNotClearedByAnAutomaticRead() {
        clipboard.copy("wl1t_signedbody")
        configure(answering(TetherWire.matched(tether: TetherWire.accepted)), mode: .automatic)

        _ = firstOpen()

        XCTAssertEqual(clipboard.text, "wl1t_signedbody")
    }

    // conformance: WL-S53
    func testAutomaticModeReadsOnTheReadQueueAndSendsTheCodeOnTheOneRequest() throws {
        clipboard.copy(liveCode)
        var queued: [() -> Void] = []
        TetherServices.readQueue = { queued.append($0) }
        let t = answering(TetherWire.matched(tether: TetherWire.accepted))
        configure(t, mode: .automatic)

        let first = firstOpen()

        XCTAssertEqual(queued.count, 1, "the read is handed to the queue, not run on the caller")
        XCTAssertEqual(clipboard.readCount, 0)
        XCTAssertNil(first)
        queued.forEach { $0() }
        XCTAssertEqual(t.bodies(forPathContaining: "/attribution/match").count, 1)
        let body = try lastMatchBody(t)
        XCTAssertEqual(body["tether_code"] as? String, liveCode)
        XCTAssertEqual(body["tether_read_mode"] as? String, "automatic")
    }

    // conformance: WL-S59
    func testAnAutomaticReadThatFindsNoCodeReportsWhy() throws {
        let t = answering(ReferralWire.matched)
        configure(t, mode: .automatic)

        _ = firstOpen()

        let body = try lastMatchBody(t)
        XCTAssertEqual(body["tether_miss_reason"] as? String, "clipboard_empty")
        XCTAssertEqual(body["tether_read_mode"] as? String, "automatic")
        XCTAssertNil(body["tether_code"])
    }

    // conformance: WL-S61
    func testALiveCodeTheServerCalledATestIsNotClearedByAPaste() {
        clipboard.copy(liveCode)
        configure(answering(TetherWire.matched(tether: TetherWire.test)), mode: .pasteButton)

        _ = paste(liveCode)

        XCTAssertEqual(clipboard.text, liveCode)
        XCTAssertEqual(clipboard.clearCount, 0)
    }

    // conformance: WL-S55
    func testATestCodeTheServerAcceptedAsLiveIsNotClearedByAPaste() {
        clipboard.copy("wl1t_signedbody")
        configure(answering(TetherWire.matched(tether: TetherWire.accepted)), mode: .pasteButton)

        _ = paste("wl1t_signedbody")

        XCTAssertEqual(clipboard.text, "wl1t_signedbody")
    }

    // conformance: WL-S54
    func testAnUnprefixedTokenFromATetherPasteIsNotSent() {
        clipboard.copy(liveToken)
        let t = answering(ReferralWire.matched)
        configure(t, mode: .pasteButton)

        let outcome = paste(liveToken)

        XCTAssertEqual(outcome?.1.miss, .clipboardEmpty)
        XCTAssertEqual(t.requestCount(forPathContaining: "/attribution/match"), 0)
    }

    func testAnUnprefixedTokenFromTheInvitationPasteStillTravelsAsRecoveryToken() throws {
        let t = answering(ReferralWire.matched)
        configure(t, mode: .pasteButton)

        WarpLink.redeemPasted(text: liveToken, stamp: nil, acceptingInvitation: true) { _, _ in }

        XCTAssertEqual(try lastMatchBody(t)["recovery_token"] as? String, liveToken)
    }
}
