import Foundation

/// A scheduled piece of work that can be called off before it runs.
protocol ScheduledWork {
    func cancel()
}

/// `DispatchWorkItem` already declares exactly this method.
extension DispatchWorkItem: ScheduledWork {}

/// Bounds ONE attempt in wall time, whatever the connection is doing.
///
/// `URLRequest.timeoutInterval` is `timeoutIntervalForRequest`, and that bounds
/// the gap BETWEEN BYTES rather than the response. A server that drips one byte
/// every half second resets it for ever, so the attempt never ends, the elapsed
/// cap is only consulted between attempts, and the twelve second worst case held
/// for a silent connection but not for a slow one. Both are the same weak uplink.
///
/// So every attempt also carries a timer of its own, fired once at that
/// attempt's deadline, which stops the request outright.
enum AttemptWatchdog {

    /// Send one attempt through `send` and guarantee it ends within `timeout`.
    ///
    /// - Parameters:
    ///   - discardConnection: called whenever this attempt's own connection is
    ///     presumed dead, so the caller can move later attempts onto a fresh
    ///     one. Two different signals trigger it. The watchdog's own deadline
    ///     calls it BEFORE the attempt is cancelled, so the connection is gone
    ///     before the retry that timeout buys is sent. A `.cancelled` this
    ///     watchdog did NOT cause calls it AFTER the result is in: that is what
    ///     a connection that died while the app was suspended looks like, and
    ///     it is indistinguishable here from a supersede or a reconfigure
    ///     cancelling on purpose. Calling it for that second case anyway is
    ///     harmless for an abandoned attempt, since nothing here rides its
    ///     connection further, and it is exactly what a still-current attempt's
    ///     retry needs. Bead: warplink-i7oa, extending warplink-qr6k.
    ///   - send: issues the request and returns its handle. Called once.
    /// - Returns: the attempt's handle, so a supersede can still stop it.
    static func bound<T>(
        timeout: TimeInterval,
        completion: @escaping (Result<T, WarpLinkError>) -> Void,
        discardConnection: @escaping () -> Void = {},
        send: (@escaping (Result<T, WarpLinkError>) -> Void) -> HTTPTask
    ) -> HTTPTask {
        let state = AttemptState()
        let timer = SDKEnvironment.armWatchdog(timeout) {
            // First, so the retry cannot be sent before the connection is gone:
            // cancelling answers the attempt, and the answer schedules the retry.
            discardConnection()
            // Outside the state's lock: cancelling calls the completion, which
            // takes it.
            state.markTimedOut()?.cancel()
        }
        let task = send { result in
            timer.cancel()
            guard !state.didTimeOut else {
                completion(asTimeout(result))
                return
            }
            if isUnwatchdoggedCancellation(result) { discardConnection() }
            completion(result)
        }
        // Fired between issuing the attempt and recording its handle: stop it
        // here, or the bound this whole type exists for would not apply.
        if state.record(task) { task.cancel() }
        return task
    }

    /// The watchdog stops an attempt by CANCELLING it, and `URLSession` reports
    /// a cancellation as `URLError(.cancelled)`. Renamed here to what it
    /// actually was: a timeout, which is more useful in a log than "cancelled"
    /// for an attempt nothing else touched.
    private static func asTimeout<T>(
        _ result: Result<T, WarpLinkError>
    ) -> Result<T, WarpLinkError> {
        guard case let .failure(.networkError(underlying)) = result,
              (underlying as? URLError)?.code == .cancelled else { return result }
        return .failure(.networkError(URLError(.timedOut)))
    }

    /// A `.cancelled` this attempt's own watchdog did not cause: either the OS
    /// reporting a connection that died while the app was suspended, or a
    /// supersede / reconfigure cancelling this attempt on purpose. The two are
    /// indistinguishable at this layer, and telling them apart is not this
    /// layer's job: `BoundedRetry` already stops a superseded or abandoned
    /// attempt before it ever asks whether to retry, so discarding the
    /// connection for one here is a wasted swap rather than a wrong retry.
    private static func isUnwatchdoggedCancellation<T>(
        _ result: Result<T, WarpLinkError>
    ) -> Bool {
        guard case let .failure(.networkError(underlying)) = result else { return false }
        return (underlying as? URLError)?.code == .cancelled
    }
}

/// One attempt's handle and whether its watchdog fired, behind a lock.
///
/// Both are written on one thread and read on another: the handle arrives on
/// whichever thread issued the attempt, the timeout on the queue the timer runs
/// on, and the answer on whichever thread the transport completes.
private final class AttemptState {

    private let lock = NSLock()
    private var timedOut = false
    private var task: HTTPTask?

    /// Mark the attempt timed out and hand back the request to stop, if one has
    /// been recorded yet.
    func markTimedOut() -> HTTPTask? {
        lock.lock(); defer { lock.unlock() }
        timedOut = true
        return task
    }

    /// Record the attempt's handle. True when the watchdog has already fired, so
    /// the caller stops it at once.
    func record(_ task: HTTPTask) -> Bool {
        lock.lock(); defer { lock.unlock() }
        self.task = task
        return timedOut
    }

    var didTimeOut: Bool {
        lock.lock(); defer { lock.unlock() }
        return timedOut
    }
}
