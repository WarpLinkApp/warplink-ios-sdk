import XCTest
@testable import WarpLink

/// The dedupe window measured elapsed time with `Date()`, which is wall clock
/// and can move backwards: NTP correcting a drifted device, or the user editing
/// the date. After a backward step the interval goes negative, every negative
/// value satisfies the bare `<`, and the handler drops every repeat tap on the
/// same link until the clock catches up to where it was.
///
/// A dropped tap is silent and looks to the user like the link is broken, so
/// the window has to survive a clock that moves the wrong way. Android hit the
/// same defect with the same shape.
final class WarpLinkDedupeClockTests: XCTestCase {

    private let url = URL(string: "https://aplnk.to/abc123")!

    override func setUp() {
        super.setUp()
        WarpLink.reset()
    }

    override func tearDown() {
        WarpLink.reset()
        super.tearDown()
    }

    // conformance: WL-S22
    func testBackwardClockStepDoesNotSuppressALaterTap() {
        var clock: TimeInterval = 10_000
        WarpLink.monotonicNow = { clock }

        XCTAssertFalse(WarpLink.shouldSuppressDuplicate(url), "first arrival")

        // Nine seconds backwards, far outside the 1s window.
        clock = 1_000
        XCTAssertFalse(
            WarpLink.shouldSuppressDuplicate(url),
            "a backward clock step swallowed a legitimate repeat tap"
        )
    }

    // conformance: WL-S22
    func testWindowStillSuppressesARepeatUnderForwardTime() {
        var clock: TimeInterval = 10_000
        WarpLink.monotonicNow = { clock }

        XCTAssertFalse(WarpLink.shouldSuppressDuplicate(url))

        // Guards the fix from overshooting into "never dedupe".
        clock = 10_000 + (WarpLink.dedupeWindow / 2)
        XCTAssertTrue(WarpLink.shouldSuppressDuplicate(url))
    }

    func testARepeatPastTheWindowIsDispatchedAgain() {
        var clock: TimeInterval = 10_000
        WarpLink.monotonicNow = { clock }

        XCTAssertFalse(WarpLink.shouldSuppressDuplicate(url))

        clock = 10_000 + (WarpLink.dedupeWindow * 2)
        XCTAssertFalse(WarpLink.shouldSuppressDuplicate(url))
    }
}
