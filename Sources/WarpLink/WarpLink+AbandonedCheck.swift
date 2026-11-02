import Foundation

/// A deferred check that `configure()` or `clearAttribution()` set aside.
struct AbandonedDeferredCheck {
    let parked: [(Result<WarpLinkDeepLink?, WarpLinkError>) -> Void]
    let task: HTTPTask?

    /// Answers the parked callers with the `.success(nil)` no-op rather than a
    /// fabricated `.notConfigured` (the SDK is configured), so an auto check
    /// parked on the abandoned one stays silent to `onLink`, which suppresses a
    /// no-match. Then cancels the request on the wire.
    ///
    /// Call outside `WarpLink.lock`: cancelling calls the completion, which
    /// takes it.
    func settle() {
        parked.forEach { pending in
            SDKEnvironment.deliver { pending(.success(nil)) }
        }
        task?.cancel()
    }
}

extension WarpLink {

    /// Marks the running check stale, so its answer is discarded, and takes
    /// what must be answered once the lock is released. The caller holds `lock`.
    static func abandonDeferredCheckLocked() -> AbandonedDeferredCheck {
        deferredCheckInFlight = false
        deferredCheckGeneration += 1
        let parked = parkedDeferredCompletions
        parkedDeferredCompletions = []
        return AbandonedDeferredCheck(parked: parked, task: takeAbandonedDeferredCheckLocked())
    }
}
