import Foundation

/// The boundaries the SDK crosses, in one place: the network, the hop onto the
/// main queue to hand a result back, the waits between attempts, the clock, the
/// install date and the app's foreground state. All of them are injectable, and
/// closing them makes a whole SDK operation run inline, so a test can call it
/// and assert on the next line instead of sleeping and hoping the work landed.
///
/// `monotonicNow` (see `WarpLink`) is the separate clock for in-process
/// intervals. `now` is the wall clock for times the SDK stores across launches.
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

    /// Builds the `Storage` for the key environment `configure()` chose. A
    /// test returns one over in-memory stores, so it never touches the host's
    /// real defaults, Keychain or Application Support directory.
    static var makeStorage: (KeyEnvironment) -> Storage = liveStorage

    /// The wall clock, for times stored across launches.
    static var now: () -> Date = { Date() }

    /// When this install was made, or nil when it cannot be read.
    static var installDate: () -> Date? = { InstallDate.ofRunningApp() }

    /// Runs `work` while the app is in the foreground: now, or at the next
    /// activation. A deferred check starts through it.
    static var whenActive: (@escaping () -> Void) -> Void = AppForeground.whenActive

    /// Restore the shipping behaviour.
    static func reset() {
        makeStorage = liveStorage
        makeTransport = liveTransport
        deliver = liveDelivery
        schedule = liveSchedule
        armWatchdog = liveWatchdog
        now = { Date() }
        installDate = { InstallDate.ofRunningApp() }
        whenActive = AppForeground.whenActive
    }

    // MARK: - Private

    private static let liveStorage: (KeyEnvironment) -> Storage = { Storage(environment: $0) }

    private static let liveTransport: () -> HTTPTransport = { URLSessionTransport() }

    /// The host contract: results arrive on the main thread, so a handler can
    /// touch UI without hopping itself.
    private static let liveDelivery: (@escaping () -> Void) -> Void = { work in
        DispatchQueue.main.async(execute: work)
    }

    /// Off the main queue: the work it schedules is an HTTP round trip, and the
    /// hop back onto main happens in `SDKEnvironment.deliver`.
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
