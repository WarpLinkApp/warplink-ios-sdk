import Foundation

/// A newer tap supersedes an older one.
///
/// The deferred path already works this way: `deferredCheckGeneration` lets an
/// abandoned check tell that it is stale and leave its successor's state alone.
/// A bounded retry gives a tap the same problem, because a tap now lives long
/// enough for the next one to arrive while it is still waiting, so the same
/// primitive is applied to taps here.
///
/// Kept out of `WarpLink+Resolve.swift` because it is a different concern from
/// resolving a link, and `WarpLink+DeferredDeepLink.swift` will want it too.
extension WarpLink {

    /// Bumped by every automatic tap. A tap captures the value and compares it
    /// before each retry and before delivering, so a newer tap stops the older
    /// one's retries and keeps it silent.
    static var tapGeneration = 0

    /// The resolve attempt a tap currently has on the wire, if any.
    ///
    /// Bumping the generation only stops the NEXT attempt. The one already sent
    /// goes on holding its connection for the rest of its timeout unless
    /// somebody cancels it, on the connection least able to spare it.
    static var inFlightTap: HTTPTask?

    /// Whether `generation` is still the newest tap. Nil is a manual caller,
    /// which is never superseded: it asked about one URL and is owed an answer.
    static func isCurrentTap(_ generation: Int?) -> Bool {
        guard let generation = generation else { return true }
        lock.lock(); defer { lock.unlock() }
        return generation == tapGeneration
    }

    /// Bump the tap generation and stop whatever the previous tap still has on
    /// the wire.
    ///
    /// Cancelling matters as much as the generation does. A cancelled request
    /// fails with `URLError(.cancelled)`, the same code the OS reports for a
    /// live connection that died in the background, so `RetryPolicy` retries it
    /// on its own (warplink-i7oa). What stops THIS run from retrying is the
    /// generation bump above happening before the cancel below: by the time the
    /// cancellation's completion runs, `isCurrentTap` for this generation is
    /// already false, and `BoundedRetry` asks that before it ever asks
    /// `RetryPolicy`. Cancelling a task that has already finished is a no-op,
    /// so nothing has to clear the handle on success.
    @discardableResult
    static func supersedeInFlightTap() -> Int {
        lock.lock()
        tapGeneration += 1
        let generation = tapGeneration
        let previous = inFlightTap
        inFlightTap = nil
        lock.unlock()
        // Outside the lock: cancelling calls the completion, which takes it.
        previous?.cancel()
        return generation
    }

    /// Record the attempt now on the wire for `generation`.
    ///
    /// A nil generation is a manual `handleDeepLink` caller, which is never
    /// superseded and so is never cancelled.
    static func setInFlightTap(_ task: HTTPTask, generation: Int?) {
        guard let generation = generation else { return }
        var stale = false
        lock.lock()
        if generation == tapGeneration {
            inFlightTap = task
        } else {
            stale = true
        }
        lock.unlock()
        // Superseded between issuing this attempt and recording it. Cancel it
        // here rather than leave a connection nobody will ever read.
        if stale { task.cancel() }
    }

    /// The attribution attempt the deferred check currently has on the wire.
    ///
    /// Same reason as `inFlightTap`: abandoning a check has to STOP its
    /// request, not merely ignore its answer. A check now lives long enough to
    /// be abandoned mid-retry, and its connection would otherwise stay open for
    /// the whole of its timeout.
    static var inFlightDeferredCheck: HTTPTask?

    /// Whether `generation` is still the live deferred check. The comparison
    /// `applyIfCurrent` already makes, hoisted so the retry can ask it too.
    static func isCurrentDeferredCheck(_ generation: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == deferredCheckGeneration
    }

    /// Record the attempt now on the wire for `generation`.
    static func setInFlightDeferredCheck(_ task: HTTPTask, generation: Int) {
        var stale = false
        lock.lock()
        if generation == deferredCheckGeneration {
            inFlightDeferredCheck = task
        } else {
            stale = true
        }
        lock.unlock()
        // Abandoned between issuing this attempt and recording it. Cancel it
        // here rather than leave a connection nobody will ever read.
        if stale { task.cancel() }
    }

    /// Hand back the abandoned check's request, for a caller that ALREADY HOLDS
    /// the lock. Cancel the result after the unlock: cancelling calls the
    /// completion, which takes the lock itself.
    ///
    /// Shaped this way because `configure()` and `reset()` bump
    /// `deferredCheckGeneration` in the same lock hold that clears the in-flight
    /// claim and drains the parked callers, and those writes have to stay atomic
    /// together. A `supersedeInFlightTap`-style helper that took the lock itself
    /// would have to split them.
    static func takeAbandonedDeferredCheckLocked() -> HTTPTask? {
        let previous = inFlightDeferredCheck
        inFlightDeferredCheck = nil
        return previous
    }

    /// Drop the dedupe claim for `url` after a failed resolve.
    ///
    /// `shouldSuppressDuplicate` stamps the claim before the request is even
    /// sent, so without this a failed resolve left the claim standing and the
    /// user's own re-tap inside the window was suppressed. Android has done this
    /// since AutoLinkHandler shipped; iOS had no equivalent.
    ///
    /// Guarded on the URL: a newer tap for a different link owns the claim now,
    /// and clearing that would let its own duplicate through.
    static func releaseDuplicateClaim(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        guard lastHandledURLString == url.absoluteString else { return }
        lastHandledURLString = nil
        lastHandledURLAt = nil
    }
}
