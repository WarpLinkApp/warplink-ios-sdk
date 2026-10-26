import Foundation

extension WarpLink {

    /// Route a result to the host's `onLink` sink on the main thread.
    ///
    /// A no-match (`.success(nil)`) is never routed to `onLink`: there is
    /// nothing to deliver, and suppressing it keeps auto-dispatch uniform with
    /// the Android and React Native SDKs, which stay silent on a miss. The
    /// manual `checkDeferredDeepLink(completion:)` API still surfaces the nil.
    static func dispatchToOnLink(_ result: Result<WarpLinkDeepLink?, WarpLinkError>) {
        if case .success(nil) = result { return }
        lock.lock(); let sink = options?.onLink; lock.unlock()
        guard let sink = sink else { return }
        SDKEnvironment.deliver { sink(result) }
    }

    /// Light dedupe so the same URL isn't dispatched twice within a short
    /// window (e.g. auto delegate + a manual host call for the same link).
    static func shouldSuppressDuplicate(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = monotonicNow()
        // The range, rather than a bare `<`, states the invariant the clock
        // gives us. Anything outside it is a fresh tap, so a source that ever
        // did run backwards would dispatch rather than silently swallow.
        if lastHandledURLString == url.absoluteString,
           let at = lastHandledURLAt,
           (now - at) >= 0, (now - at) < dedupeWindow {
            return true
        }
        lastHandledURLString = url.absoluteString
        lastHandledURLAt = now
        return false
    }
}
