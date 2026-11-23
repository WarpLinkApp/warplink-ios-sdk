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

    /// Routes an attribution result to `onLink` and records the link it
    /// delivered. A later Tether match replaces that link only when this record
    /// says `onLink` really received it, across launches. A deep link tapped in
    /// the app goes through `dispatchToOnLink` and is not recorded.
    ///
    /// `ifGeneration` is required: the store's `attributionClearGeneration` as read
    /// when the link was found, so no caller can skip the check. The record write checks it
    /// under the store's lock, and the queued callback checks it again right
    /// before `onLink` runs, so a `clearAttribution()` or `clearAll()` that lands
    /// in between wins: nothing is written and the stale link is not sent. The
    /// callback itself runs outside any lock.
    static func dispatchAttributionToOnLink(
        _ result: Result<WarpLinkDeepLink?, WarpLinkError>,
        ifGeneration: Int
    ) {
        if case .success(nil) = result { return }
        lock.lock(); let sink = options?.onLink; let store = storage; lock.unlock()
        guard let sink = sink else { return }
        guard let store = store else {
            SDKEnvironment.deliver { sink(result) }
            return
        }
        let generation = ifGeneration
        if case let .success(link?) = result,
           !store.recordOnLinkDelivery(link.routeIdentity, ifGeneration: generation) {
            return
        }
        SDKEnvironment.deliver {
            guard store.isCurrentAttributionGeneration(generation) else { return }
            sink(result)
        }
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
