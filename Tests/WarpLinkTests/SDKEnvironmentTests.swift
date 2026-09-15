import XCTest
@testable import WarpLink

/// `SDKEnvironment` exists so a test can close the SDK's three asynchronous
/// boundaries. That is only safe while the closing is undone afterwards.
///
/// A leak here does not fail loudly. It hands one suite's stub to the next one,
/// which then passes or fails for reasons that have nothing to do with what it
/// is testing, and the trail leads back to a file nobody was editing. So the
/// restoration is asserted directly rather than assumed.
final class SDKEnvironmentTests: XCTestCase {

    override func setUp() {
        super.setUp()
        WarpLink.reset()
    }

    override func tearDown() {
        WarpLink.reset()
        super.tearDown()
    }

    func testResetRestoresTheLiveTransport() {
        makeSDKSynchronous(InlineTransport.serving { _ in [:] })
        XCTAssertTrue(
            SDKEnvironment.makeTransport() is InlineTransport,
            "precondition: the stub is installed"
        )

        WarpLink.reset()

        XCTAssertTrue(
            SDKEnvironment.makeTransport() is URLSessionTransport,
            "a leaked stub would answer the next suite's requests"
        )
    }

    func testResetRestoresTheLiveDelivery() {
        makeSDKSynchronous(InlineTransport.serving { _ in [:] })
        let inlineRuns = Counter()
        SDKEnvironment.deliver { inlineRuns.increment() }
        XCTAssertEqual(inlineRuns.value, 1, "precondition: delivery is synchronous")

        WarpLink.reset()

        // Live delivery hops to the main queue. This test body IS the main
        // queue, so the work cannot have run by the next line. A leaked
        // synchronous delivery would run it immediately, and that is the whole
        // difference being asserted.
        let liveRuns = Counter()
        SDKEnvironment.deliver { liveRuns.increment() }
        XCTAssertEqual(
            liveRuns.value, 0,
            "live delivery must queue onto the main thread, not run inline"
        )
    }

    func testResetRestoresTheLiveSchedule() {
        makeSDKSynchronous(InlineTransport.serving { _ in [:] })
        let inlineRuns = Counter()
        SDKEnvironment.schedule(0) { inlineRuns.increment() }
        XCTAssertEqual(inlineRuns.value, 1, "precondition: the wait is closed")

        WarpLink.reset()

        // A live wait is a real deadline on a background queue, so asking for a
        // full minute and finding the work already done can only mean the
        // closed version leaked. That leak is the expensive one: a leaked
        // `ScheduleRecorder` would run every later suite's backoff at once, and
        // a retry test that never waits proves nothing.
        let liveRuns = Counter()
        SDKEnvironment.schedule(60) { liveRuns.increment() }
        XCTAssertEqual(liveRuns.value, 0, "a live wait must not run inline")
    }

    /// The seams are independent, so restoring one must not be mistaken for
    /// restoring the rest. Without this, a `reset()` that put back only the
    /// transport would still satisfy the transport test above.
    func testResetRestoresEverySeamTogether() {
        makeSDKSynchronous(InlineTransport.serving { _ in [:] })
        // The fourth seam is faked here rather than in `makeSDKSynchronous`,
        // which deliberately leaves it alone: a watchdog that runs at once
        // would abandon every attempt in every suite that closes the other
        // three. It still has to come back, and only this test says so.
        SDKEnvironment.armWatchdog = { _, work in
            work()
            return DispatchWorkItem {}
        }
        let firedInline = Counter()
        _ = SDKEnvironment.armWatchdog(60) { firedInline.increment() }
        XCTAssertEqual(firedInline.value, 1, "precondition: the watchdog is closed")

        WarpLink.reset()

        let ranInline = Counter()
        SDKEnvironment.deliver { ranInline.increment() }
        SDKEnvironment.schedule(60) { ranInline.increment() }
        // Cancelled at once, because a live watchdog really is armed: the leak
        // being tested for would have run the work before `cancel()` could.
        SDKEnvironment.armWatchdog(60) { ranInline.increment() }.cancel()
        XCTAssertTrue(SDKEnvironment.makeTransport() is URLSessionTransport)
        XCTAssertEqual(ranInline.value, 0)
    }
}
