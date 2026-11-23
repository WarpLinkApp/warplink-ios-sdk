import XCTest
@testable import WarpLink

final class TetherCodeTests: XCTestCase {

    private let body = ReferralTokenFixture.token(expiresAt: 1_900_000_000)

    // conformance: WL-S54
    func testLiveCodeIsRecognisedAfterTrimming() {
        let code = TetherCode.parse("  \n wl1_\(body) \t")
        XCTAssertEqual(code, .live("wl1_\(body)"))
        XCTAssertEqual(code?.wireText, "wl1_\(body)")
    }

    // conformance: WL-S54
    func testTestCodeIsCheckedBeforeTheLivePrefix() {
        XCTAssertEqual(TetherCode.parse("wl1t_abc123"), .test("wl1t_abc123"))
    }

    // conformance: WL-S54
    func testTextWithoutAKnownPrefixIsNeverACode() {
        for text in [
            "", "   ", "hello", "https://example.com/?c=wl1_\(body)", "WL1_\(body)",
            "xwl1_\(body)", "wl2_abc", "wl1", "wl1t",
        ] {
            XCTAssertNil(TetherCode.parse(text), "\(text) must not parse")
        }
    }

    // conformance: WL-S54
    func testAPrefixWithNoBodyIsNotACode() {
        XCTAssertNil(TetherCode.parse("wl1_"))
        XCTAssertNil(TetherCode.parse("wl1t_ "))
    }

    // conformance: WL-S54
    func testACodeLongerThanTheWireLimitIsNotACode() {
        XCTAssertNil(TetherCode.parse("wl1_" + String(repeating: "a", count: 197)))
        XCTAssertNotNil(TetherCode.parse("wl1_" + String(repeating: "a", count: 196)))
    }

    func testLegacyInvitationParsesWhenTheExplicitPathAsksForIt() {
        XCTAssertEqual(TetherCode.parse(body, acceptingInvitation: true), .invitation(body))
        XCTAssertEqual(TetherCode.parse(" \(body)\n", acceptingInvitation: true)?.wireText, body)
    }

    func testLegacyInvitationIsNotACodeUnlessAsked() {
        XCTAssertNil(TetherCode.parse(body))
    }

    func testAnAlmostInvitationIsNotACode() {
        XCTAssertNil(TetherCode.parse(String(body.dropLast()), acceptingInvitation: true))
    }

    func testLiveCodeTakesItsExpiryFromTheTokenBody() {
        let code = TetherCode.parse("wl1_\(body)")
        XCTAssertEqual(
            code?.expiresAt(now: Date(timeIntervalSince1970: 1)),
            Date(timeIntervalSince1970: 1_900_000_000)
        )
    }

    func testCodesWithoutAReadableExpiryGetTheirLifetimeFromTheKind() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(TetherCode.parse("wl1_opaque")?.expiresAt(now: now), now.addingTimeInterval(86_400))
        XCTAssertEqual(TetherCode.parse("wl1t_opaque")?.expiresAt(now: now), now.addingTimeInterval(900))
    }

    func testWireModesAndReasonsMatchTheSharedContract() {
        XCTAssertEqual(TetherReadMode.pasteButton.rawValue, "paste_button")
        XCTAssertEqual(TetherReadMode.automatic.rawValue, "automatic")
        XCTAssertEqual(TetherReadMode.onCall.rawValue, "on_call")
        XCTAssertEqual(
            Set(TetherMissReason.allCases.map(\.rawValue)),
            [
                "paste_not_allowed", "clipboard_empty", "in_app_browser", "expired",
                "other_app", "link_ended", "older_sdk",
            ]
        )
    }
}
