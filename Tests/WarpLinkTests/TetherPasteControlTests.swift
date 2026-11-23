#if canImport(UIKit)
import UIKit
import XCTest
@testable import WarpLink

/// The UIKit paste control takes its clipboard stamp at the tap, and takes
/// older invitation text only when the app asks for the older result.
/// Runs in the iOS simulator; `swift test` on macOS has no UIKit.
@available(iOS 16.0, *)
final class TetherPasteControlTests: TetherTestCase {

    private func tap(_ button: WarpLinkUIPasteButton, text: String) {
        button.paste(itemProviders: [NSItemProvider(object: text as NSString)])
    }

    // conformance: WL-S55
    func testAnAcceptedCodeIsClearedWhenNothingWasCopiedSinceTheTap() {
        clipboard.copy(liveCode)
        configure(answering(TetherWire.matched(tether: TetherWire.accepted)), mode: .pasteButton)
        let done = expectation(description: "tether result")
        let button = WarpLinkUIPasteButton()
        button.onTether = { _ in done.fulfill() }

        tap(button, text: liveCode)
        wait(for: [done], timeout: 5)

        XCTAssertEqual(clipboard.clearCount, 1)
        XCTAssertNil(clipboard.text)
    }

    func testACopyThatLandsAfterTheTapIsNeverCleared() {
        clipboard.copy(liveCode)
        configure(answering(TetherWire.matched(tether: TetherWire.accepted)), mode: .pasteButton)
        let done = expectation(description: "tether result")
        let button = WarpLinkUIPasteButton()
        button.onTether = { _ in done.fulfill() }

        tap(button, text: liveCode)
        clipboard.copy("newer")
        wait(for: [done], timeout: 5)

        XCTAssertEqual(clipboard.text, "newer")
        XCTAssertEqual(clipboard.clearCount, 0)
    }

    // conformance: WL-S54
    func testATetherControlDoesNotSendAnUnprefixedToken() {
        let t = answering(ReferralWire.matched)
        configure(t, mode: .pasteButton)
        let done = expectation(description: "tether result")
        let button = WarpLinkUIPasteButton()
        button.onTether = { _ in done.fulfill() }

        tap(button, text: liveToken)
        wait(for: [done], timeout: 5)

        XCTAssertEqual(t.requestCount(forPathContaining: "/attribution/match"), 0)
    }

    func testAnInvitationControlStillSendsAnUnprefixedToken() throws {
        let t = answering(ReferralWire.matched)
        configure(t, mode: .pasteButton)
        let done = expectation(description: "result")
        let button = WarpLinkUIPasteButton { _ in done.fulfill() }

        tap(button, text: liveToken)
        wait(for: [done], timeout: 5)

        XCTAssertEqual(try lastMatchBody(t)["recovery_token"] as? String, liveToken)
    }
}
#endif
