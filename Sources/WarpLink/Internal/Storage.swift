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

    private static let apiKeyValidatedAtKey = "warplink_api_key_validated_at"
    /// The attempted flag, in the install marker store like the gate: it
    /// describes this install's attempts, so it must not come back from a
    /// restore. 1.1.0 pre-release builds kept it in UserDefaults; that key
    /// is in `legacyKeys` so it is cleaned up.
    private static let attemptedMarker = "warplink_attribution_attempted"
    private static let cachedAttrKey = "warplink_cached_attribution"
    private static let domainsKey = "warplink_cached_domains"
    /// The gate, in the install marker store.
    private static let installCompleteMarker = "warplink_attribution_complete"
    /// The device-seen marker, in the durable store. Same name as 1.1.0's
    /// Keychain marker on purpose: that marker already meant "this device
    /// completed attribution for this app", which is precisely this job.
    private static let deviceSeenMarker = "warplink_attribution_complete"
    /// Per-install fallback for hosts where the install marker store cannot
    /// write. `UserDefaults` is restored from a backup, so this trades the
    /// restore property away to keep the at-most-once guarantee within an
    /// install. That is the safer half to lose: a re-fire on every launch would
    /// double-count an install on every single launch.
    private static let installCompleteFallbackKey = "warplink_attribution_complete_fallback"

    /// Keys 1.0.x wrote and nothing reads any more: its first-launch flag and
    /// its typed cache. The cache is not migrated: attribution under 1.0.x was
    /// broken, so almost no device holds a match worth carrying, and an
    /// upgrading user simply sees `attributionResult` as nil until their next
    /// install. Removed on construction so they do not sit in the plist forever.
    private static let legacyKeys = [
        "warplink_first_launch",
        "warplink_has_cached_attribution",
        "warplink_cached_link_id",
        "warplink_cached_destination",
        "warplink_cached_deep_link_url",
        "warplink_cached_is_deferred",
        "warplink_cached_match_type",
        "warplink_cached_match_confidence",
        "warplink_cached_custom_params",
        "warplink_attribution_attempted",
    ]

    private let defaults: UserDefaults
    private let markerStore: DurableMarkerStore
    private let installMarkerStore: InstallMarkerStore

    init(
        defaults: UserDefaults = .standard,
        markerStore: DurableMarkerStore = KeychainStore(),
        installMarkerStore: InstallMarkerStore = BackupExcludedFileStore()
    ) {
        self.defaults = defaults
        self.markerStore = markerStore
        self.installMarkerStore = installMarkerStore
        Self.legacyKeys.forEach { defaults.removeObject(forKey: $0) }

        // A cached match with an open gate is a ghost: the two are written
        // together, and only a restore brings UserDefaults back without the
        // backup-excluded gate. Left alone, attributionResult replays the
        // previous install's match until the new check lands.
        if isReinstall, defaults.object(forKey: Self.cachedAttrKey) != nil {
            defaults.removeObject(forKey: Self.cachedAttrKey)
        }
    }

    // MARK: - Attribution lifecycle (split: attempted vs completed)

    /// The gate: whether attribution has definitively completed for this
    /// install. When `true`, the deferred check returns cached data with no
    /// network call. Deliberately not durable across app deletion, because a
    /// reinstall counts as an install and has to be attributed again.
    var isAttributionComplete: Bool {
        if installMarkerStore.isMarked(Self.installCompleteMarker) { return true }
        return defaults.bool(forKey: Self.installCompleteFallbackKey)
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
        markerStore.isMarked(Self.deviceSeenMarker)
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
    /// A failed device-seen write costs the reinstall tag. The server reads
    /// that tag to decide whether the device-id branch may reuse the previous
    /// install's row, so a lost write can route the next reinstall to the old
    /// campaign. The Keychain write is add-before-delete so a failed write can
    /// never erase a marker that is already there.
    func markAttributionComplete() {
        if !installMarkerStore.mark(Self.installCompleteMarker) {
            defaults.set(true, forKey: Self.installCompleteFallbackKey)
        }
        markerStore.mark(Self.deviceSeenMarker)
    }

    /// Whether at least one attribution attempt has been made this install.
    /// Distinguishes a brand-new first launch from a retry after a prior
    /// attempt failed (offline).
    var hasAttemptedAttribution: Bool {
        get { installMarkerStore.isMarked(Self.attemptedMarker) }
        set {
            if newValue {
                installMarkerStore.mark(Self.attemptedMarker)
            } else {
                installMarkerStore.clear(Self.attemptedMarker)
            }
        }
    }

    // MARK: - API key validation cache

    var apiKeyValidatedAt: Date? {
        get {
            let interval = defaults.double(forKey: Self.apiKeyValidatedAtKey)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let date = newValue {
                defaults.set(date.timeIntervalSince1970, forKey: Self.apiKeyValidatedAtKey)
            } else {
                defaults.removeObject(forKey: Self.apiKeyValidatedAtKey)
            }
        }
    }

    var isApiKeyValidationCacheValid: Bool {
        guard let validatedAt = apiKeyValidatedAt else { return false }
        return Date().timeIntervalSince(validatedAt) < 86400
    }

    // MARK: - Cached link domains (from /sdk/validate)

    var cachedDomains: [String] {
        get { defaults.stringArray(forKey: Self.domainsKey) ?? [] }
        set { defaults.set(newValue, forKey: Self.domainsKey) }
    }

    // MARK: - Cached attribution payload

    var cachedAttribution: WarpLinkDeepLink? {
        get {
            guard let data = defaults.data(forKey: Self.cachedAttrKey) else { return nil }
            return try? JSONDecoder().decode(WarpLinkDeepLink.self, from: data)
        }
        set {
            if let value = newValue, let data = try? JSONEncoder().encode(value) {
                defaults.set(data, forKey: Self.cachedAttrKey)
            } else {
                defaults.removeObject(forKey: Self.cachedAttrKey)
            }
        }
    }

    /// Clear all stored SDK data. Used for testing.
    func clearAll() {
        defaults.removeObject(forKey: Self.apiKeyValidatedAtKey)
        defaults.removeObject(forKey: Self.cachedAttrKey)
        defaults.removeObject(forKey: Self.domainsKey)
        defaults.removeObject(forKey: Self.installCompleteFallbackKey)
        installMarkerStore.clear(Self.installCompleteMarker)
        installMarkerStore.clear(Self.attemptedMarker)
        markerStore.clear(Self.deviceSeenMarker)
    }
}
