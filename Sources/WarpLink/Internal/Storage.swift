import Foundation

/// Persists SDK state.
///
/// Per-install state (cached attribution payload, cached domains,
/// key-validation timestamp) lives in `UserDefaults`. The attempted flag
/// lives in the install marker store instead: see below.
///
/// Attribution completion is tracked by two markers with deliberately opposite
/// lifetimes, because they answer different questions:
///
/// - the **gate** (`InstallMarkerStore`) answers "has attribution completed for
///   THIS install?" and dies with the app, so a reinstall is attributed again;
/// - the **device-seen marker** (`DurableMarkerStore`) answers "has this device
///   ever been attributed for this app?", outlives the app, and gates nothing.
///
/// A reinstall is the state where the device has been seen but the gate is open.
final class Storage {

    let keys: StorageKeys
    let defaults: UserDefaults
    private let markerStore: DurableMarkerStore
    let installMarkerStore: InstallMarkerStore
    private let installationIds: InstallationIdStore
    /// Guards `clearGeneration` and the delivered-link record together.
    let deliveryLock = NSLock()
    var clearGeneration = 0

    init(
        environment: KeyEnvironment = .production,
        defaults: UserDefaults = .standard,
        markerStore: DurableMarkerStore = KeychainStore(),
        installMarkerStore: InstallMarkerStore = BackupExcludedFileStore()
    ) {
        self.keys = StorageKeys(environment: environment)
        self.defaults = defaults
        self.markerStore = markerStore
        self.installMarkerStore = installMarkerStore
        self.installationIds = InstallationIdStore(store: installMarkerStore, key: keys.installationId)
        if environment == .production {
            StorageKeys.legacy.forEach { defaults.removeObject(forKey: $0) }
        }

        // A cached match with an open gate is a ghost: the two are written
        // together, and only a restore brings UserDefaults back without the
        // backup-excluded gate. Left alone, attributionResult replays the
        // previous install's match until the new check lands.
        if isReinstall, defaults.object(forKey: keys.cachedAttribution) != nil {
            defaults.removeObject(forKey: keys.cachedAttribution)
            defaults.removeObject(forKey: keys.onLinkDelivered)
        }
    }

    // MARK: - Attribution lifecycle

    /// The gate: whether attribution has definitively completed for this
    /// install. When `true`, the deferred check returns cached data with no
    /// network call. Deliberately not durable across app deletion, because a
    /// reinstall counts as an install and has to be attributed again.
    var isAttributionComplete: Bool {
        if installMarkerStore.isMarked(keys.installCompleteMarker) { return true }
        return defaults.bool(forKey: keys.installCompleteFallback)
    }

    /// Whether this device has ever completed attribution for this app, under
    /// this install or an earlier one. Never gates anything; it only decides
    /// whether the next attribution is reported as a reinstall.
    ///
    /// 1.0.x wrote `warplink_first_launch = false` at the START of its check,
    /// before anything was sent, so it proves only that a check began. It is
    /// deliberately not read: it lives in UserDefaults, which a restore brings
    /// back, and reading it mislabelled a first install as a reinstall.
    var hasDeviceEverCompletedAttribution: Bool {
        markerStore.isMarked(keys.deviceSeenMarker)
    }

    /// The `is_reinstall` value for the next attribution request: this device
    /// was attributed before, but not under the install running now.
    var isReinstall: Bool {
        hasDeviceEverCompletedAttribution && !isAttributionComplete
    }

    /// Mark attribution complete. Called ONLY on a definitive server response
    /// (match or no-match), never merely because a check was started.
    ///
    /// Writes both markers: the gate closes for this install, and the device is
    /// recorded as seen so the next install reports itself as a reinstall.
    ///
    /// If the gate can't be written, fall back to `UserDefaults` so the result
    /// is still delivered at most once for this install instead of re-firing on
    /// every launch.
    ///
    /// A failed device-seen write costs the reinstall tag. The server reads
    /// that tag to decide whether the device-id branch may reuse the previous
    /// install's row, so a lost write can route the next reinstall to the old
    /// campaign. The Keychain write is add-before-delete so a failed write can
    /// never erase a marker that is already there.
    func markAttributionComplete() {
        if !installMarkerStore.mark(keys.installCompleteMarker) {
            defaults.set(true, forKey: keys.installCompleteFallback)
        }
        markerStore.mark(keys.deviceSeenMarker)
    }

    /// Whether at least one attribution attempt has been made this install.
    /// Distinguishes a brand-new first launch from a retry after a prior
    /// attempt failed (offline).
    var hasAttemptedAttribution: Bool {
        get { installMarkerStore.isMarked(keys.attemptedMarker) }
        set {
            if newValue {
                installMarkerStore.mark(keys.attemptedMarker)
            } else {
                installMarkerStore.clear(keys.attemptedMarker)
            }
        }
    }

    /// The id of this install, sent on every attribution match.
    var installationId: String { installationIds.id }

    /// Forget this environment's attribution: the cached match, the gate, the
    /// attempted flag, the installation id and the device-seen marker. The next
    /// check attributes again as a first install. Key validation and cached domains describe the
    /// key, not the install, so they stay.
    ///
    /// Every marker is tried even when one fails to delete.
    ///
    /// - Returns: false when a marker could not be deleted, so the completion
    ///   gate may still be closed.
    @discardableResult
    func clearAttribution() -> Bool {
        defaults.removeObject(forKey: keys.cachedAttribution)
        forgetOnLinkDelivery()
        defaults.removeObject(forKey: keys.installCompleteFallback)
        let cleared = [
            installMarkerStore.clear(keys.installCompleteMarker),
            installMarkerStore.clear(keys.attemptedMarker),
            installationIds.clear(),
            markerStore.clear(keys.deviceSeenMarker),
        ] + clearCheckState()
        return !cleared.contains(false)
    }

    /// Clear all stored SDK data.
    func clearAll() {
        defaults.removeObject(forKey: keys.apiKeyValidatedAt)
        defaults.removeObject(forKey: keys.cachedAttribution)
        forgetOnLinkDelivery()
        defaults.removeObject(forKey: keys.domains)
        defaults.removeObject(forKey: keys.installCompleteFallback)
        installMarkerStore.clear(keys.installCompleteMarker)
        installMarkerStore.clear(keys.attemptedMarker)
        installationIds.clear()
        markerStore.clear(keys.deviceSeenMarker)
        clearCheckState()
        defaults.removeObject(forKey: keys.sdkPolicy)
    }
}
