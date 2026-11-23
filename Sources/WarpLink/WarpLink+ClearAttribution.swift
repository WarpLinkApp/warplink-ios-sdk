import Foundation

/// Why `clearAttribution()` could not finish.
enum ClearAttributionError: LocalizedError {
    case markerNotDeleted

    var errorDescription: String? {
        "Could not clear stored attribution data."
    }
}

extension WarpLink {

    /// Clears the attribution this device stored for a Test key, so a first
    /// install can be tested again without deleting the app.
    ///
    /// Test only. With a `wl_live_` key this does nothing and returns
    /// `.success`: live attribution is never cleared from the device.
    ///
    /// For a Test key it clears the cached match, the markers that record an
    /// attempt and a completed attribution, and any held referral invitation,
    /// then runs a new attribution check when `autoDeferredCheck` is on. A check
    /// already on the wire is discarded and cannot refill what was cleared.
    ///
    /// Only state on this device is cleared. Server records are not deleted,
    /// and the new check is not promised a new install record. Test state is
    /// stored apart from live state, so a live build on the same device is
    /// untouched.
    ///
    /// - Returns: `.failure(.notConfigured)` before `configure(apiKey:options:)`.
    ///   `.failure(.decodingError)` when a marker on this device could not be
    ///   deleted: the cache and referral state are cleared, but the first
    ///   install gate may still be closed.
    @discardableResult
    public static func clearAttribution() -> Result<Void, WarpLinkError> {
        lock.lock()
        guard let key = apiKey, let store = storage else {
            lock.unlock()
            return .failure(.notConfigured)
        }
        guard KeyEnvironment(apiKey: key) == .test else {
            lock.unlock()
            return .success(())
        }
        // One lock hold for the generation bump and every clear: a check or a
        // redeem that lands after finds its state stale and writes nothing, and
        // a concurrent configure() cannot point the referral clear at the stores
        // of another key.
        let abandoned = abandonDeferredCheckLocked()
        let cleared = store.clearAttribution()
        ReferralServices.clearAll()
        TetherServices.clearAll()
        let autoCheck = options?.autoDeferredCheck ?? false
        lock.unlock()

        abandoned.settle(givingBackCount: false)
        guard cleared else { return .failure(.decodingError(ClearAttributionError.markerNotDeleted)) }
        if autoCheck { runAutoDeferredCheck() }
        return .success(())
    }
}
