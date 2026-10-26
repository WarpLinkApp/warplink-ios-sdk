import Foundation

extension WarpLink {

    /// Records the exact match an invitation redeemed, and stops the automatic
    /// deferred check, which may still be on the wire.
    ///
    /// The check's later answer is an estimate or a no-match. Left alone it
    /// would route a second, weaker link to `onLink` and overwrite the cache.
    /// The generation bump makes it answer the silent no-op, as a reconfigure
    /// does, and a caller parked on it gets the exact match instead.
    static func recordRedeemedMatch(_ link: WarpLinkDeepLink, store: Storage) {
        lock.lock()
        store.markAttributionComplete()
        store.cachedAttribution = link
        deferredCheckInFlight = false
        deferredCheckGeneration += 1
        let parked = parkedDeferredCompletions
        parkedDeferredCompletions = []
        let abandonedCheck = takeAbandonedDeferredCheckLocked()
        lock.unlock()

        parked.forEach { pending in SDKEnvironment.deliver { pending(.success(link)) } }
        abandonedCheck?.cancel()
    }
}
