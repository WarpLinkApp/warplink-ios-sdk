import Foundation

/// The three boundaries that make this SDK asynchronous, in one place.
///
/// Everything the SDK does for a caller crosses at least two of them: an HTTP
/// round trip, and a hop onto the main queue to hand the result back. A bounded
/// retry crosses a third, the wait it spends between one attempt and the next.
/// All three are injectable here, and closing them makes a whole SDK operation
/// run inline, so a test can call it and assert on the next line.
///
/// That matters because the alternative is what the suite used to do: sleep for
/// a fixed interval and hope the work landed inside it. A sleep is a race with
/// no observer. It passes on a quiet machine and fails on a loaded one, which is
/// exactly what happened to `WarpLinkAutoWireTests` under a parallel build.
///
/// A fake clock does not help here, which is worth stating because it is the
/// obvious idea. `monotonicNow` is injectable precisely because the dedupe
/// window *reads* a clock. Nothing on this path does: `URLSession` answers when
/// I/O completes, `DispatchQueue.main` answers when the queue drains, and
/// `asyncAfter` answers when its own deadline arrives. None of the three
/// consults a clock you can move.
///
/// Restored by `WarpLink.reset()`, so an injection cannot leak into the next
/// test.
enum SDKEnvironment {

    /// Builds the transport for each new `APIClient`. A factory rather than a
    /// single instance because `configure()` may replace the client, and each
    /// one should get a transport in the state the environment is in then.
    static var makeTransport: () -> HTTPTransport = liveTransport

    /// Hands a completed result back to the host. Every SDK callback goes
    /// through here, so overriding it redirects all of them at once.
    static var deliver: (@escaping () -> Void) -> Void = liveDelivery

    /// Runs `work` after `delay` seconds. The third boundary: a bounded retry
    /// has to wait between attempts, and a test that really waited would spend
    /// the budget it exists to check. Overriding this runs the retry inline.
    static var schedule: (TimeInterval, @escaping () -> Void) -> Void = liveSchedule

    /// Runs `work` after `delay` seconds and hands back a handle that calls it
    /// off. The fourth boundary: each attempt's own watchdog.
    ///
    /// Deliberately NOT `schedule`, even though both are delays. A test closes
    /// `schedule` by running its work AT ONCE, which is right for a wait between
    /// attempts and catastrophic for a watchdog: every attempt would be
    /// abandoned before it was even sent. It also has to be cancellable, which a
    /// wait never is.
    static var armWatchdog: (TimeInterval, @escaping () -> Void) -> ScheduledWork = liveWatchdog

    /// Restore the shipping behaviour.
    static func reset() {
        makeTransport = liveTransport
        deliver = liveDelivery
        schedule = liveSchedule
        armWatchdog = liveWatchdog
    }

    // MARK: - Private

    private static let liveTransport: () -> HTTPTransport = { URLSessionTransport() }

    /// The host contract: results arrive on the main thread, so a handler can
    /// touch UI without hopping itself.
    private static let liveDelivery: (@escaping () -> Void) -> Void = { work in
        DispatchQueue.main.async(execute: work)
    }

    /// Off the main queue: the work it schedules is an HTTP round trip, and the
    /// hop back onto main happens in `SDKEnvironment.deliver` as it always did.
    private static let liveSchedule: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + delay, execute: work
        )
    }

    /// Off the main queue for the same reason as `liveSchedule`, and a
    /// `DispatchWorkItem` rather than a bare closure because the attempt that
    /// answers in time has to be able to call its watchdog off.
    private static let liveWatchdog: (TimeInterval, @escaping () -> Void) -> ScheduledWork = {
        delay, work in
        let item = DispatchWorkItem(block: work)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + delay, execute: item
        )
        return item
    }
}
