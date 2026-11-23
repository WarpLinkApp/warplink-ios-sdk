import XCTest
@testable import WarpLink

/// What the SDK reads, what it keeps, and when it empties the clipboard.
final class TetherReaderTests: XCTestCase {

    private let clipboard = FakeClipboard()
    private let code = "wl1_" + ReferralTokenFixture.token(expiresAt: 1_900_000_000)

    private func claim(_ reading: TetherReader.Reading) -> TetherClaim? {
        if case let .code(claim) = reading { return claim }
        return nil
    }

    private func reason(_ reading: TetherReader.Reading) -> TetherMissReason? {
        if case let .miss(reason) = reading { return reason }
        return nil
    }

    // conformance: WL-S53
    func testAPastedCodeIsTakenWithoutReadingTheClipboard() {
        clipboard.copy(code)

        let reading = TetherReader.reading(of: code, stamp: clipboard.changeCount)

        XCTAssertEqual(claim(reading)?.code, .live(code))
        XCTAssertEqual(clipboard.readCount, 0, "the paste control already did the read")
    }

    // conformance: WL-S53
    func testAnOwnReadTakesTheStampBeforeItReadsTheText() {
        clipboard.copy(code)
        let stamp = clipboard.changeCount

        let taken = claim(TetherReader.read(clipboard))

        XCTAssertEqual(taken?.changeCount, stamp)
        XCTAssertEqual(clipboard.readCount, 1)
    }

    // conformance: WL-S54
    func testTextThatIsNotACodeIsAMissAndIsNotKept() {
        clipboard.copy("my cat's name is Pepper")

        let reading = TetherReader.read(clipboard)

        XCTAssertEqual(reason(reading), .clipboardEmpty)
        XCTAssertNil(claim(reading))
    }

    // conformance: WL-S59
    func testAnEmptyClipboardIsReadAsEmptyWithoutAPrompt() {
        let reading = TetherReader.read(clipboard)

        XCTAssertEqual(reason(reading), .clipboardEmpty)
        XCTAssertEqual(clipboard.readCount, 0, "hasStrings shows no prompt, so the text is not read")
    }

    // conformance: WL-S59
    func testARefusedPasteIsReadAsNotAllowed() {
        clipboard.copy(code)
        clipboard.denied = true

        XCTAssertEqual(reason(TetherReader.read(clipboard)), .pasteNotAllowed)
    }

    // conformance: WL-S57
    func testABuildWithNoClipboardReadsNothingAndSaysOlderSdk() {
        clipboard.copy(code)
        clipboard.canRead = false

        XCTAssertEqual(reason(TetherReader.read(clipboard)), .olderSdk)
        XCTAssertEqual(clipboard.readCount, 0)
    }

    // conformance: WL-S55
    func testAnUnchangedClipboardIsEmptied() {
        clipboard.copy(code)
        let held = TetherClaim(code: .live(code), changeCount: clipboard.changeCount)

        held.clearIfHeld(on: clipboard)

        XCTAssertEqual(clipboard.clearCount, 1)
        XCTAssertNil(clipboard.text)
    }

    // conformance: WL-S55
    func testAClipboardThatChangedSinceIsLeftAlone() {
        clipboard.copy(code)
        let held = TetherClaim(code: .live(code), changeCount: clipboard.changeCount)
        clipboard.copy("something the person copied next")

        held.clearIfHeld(on: clipboard)

        XCTAssertEqual(clipboard.clearCount, 0)
        XCTAssertEqual(clipboard.text, "something the person copied next")
    }

    // conformance: WL-S55
    func testACodeThatDidNotComeFromTheClipboardClearsNothing() {
        clipboard.copy(code)

        TetherClaim(code: .live(code), changeCount: nil).clearIfHeld(on: clipboard)

        XCTAssertEqual(clipboard.clearCount, 0)
    }

    // conformance: WL-S57
    func testTheClipboardOfABuildWithNoAccessNeverClears() {
        let none = NoClipboard()
        TetherClaim(code: .live(code), changeCount: 0).clearIfHeld(on: none)

        XCTAssertFalse(none.canRead)
        XCTAssertNil(none.readString())
    }
}
