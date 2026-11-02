import Foundation

/// Every name `Storage` persists under, in one environment's namespace.
struct StorageKeys {

    let apiKeyValidatedAt: String
    /// The attempted flag, in the install marker store like the gate: it
    /// describes this install's attempts, so it must not come back from a
    /// restore. 1.1.0 pre-release builds kept it in UserDefaults; that key
    /// is in `legacy` so it is cleaned up.
    let attemptedMarker: String
    let cachedAttribution: String
    let domains: String
    /// The gate, in the install marker store.
    let installCompleteMarker: String
    /// The device-seen marker, in the durable store. Same name as 1.1.0's
    /// Keychain marker on purpose: that marker already meant "this device
    /// completed attribution for this app", which is precisely this job.
    let deviceSeenMarker: String
    /// Per-install fallback for hosts where the install marker store cannot
    /// write. `UserDefaults` is restored from a backup, so this trades the
    /// restore property away to keep the at-most-once guarantee within an
    /// install. That is the safer half to lose: a re-fire on every launch would
    /// double-count an install on every single launch.
    let installCompleteFallback: String

    init(environment: KeyEnvironment = .production) {
        apiKeyValidatedAt = environment.scoped("warplink_api_key_validated_at")
        attemptedMarker = environment.scoped("warplink_attribution_attempted")
        cachedAttribution = environment.scoped("warplink_cached_attribution")
        domains = environment.scoped("warplink_cached_domains")
        installCompleteMarker = environment.scoped("warplink_attribution_complete")
        deviceSeenMarker = environment.scoped("warplink_attribution_complete")
        installCompleteFallback = environment.scoped("warplink_attribution_complete_fallback")
    }

    /// Keys 1.0.x wrote and nothing reads any more: its first-launch flag and
    /// its typed cache. The cache is not migrated: attribution under 1.0.x was
    /// broken, so almost no device holds a match worth carrying, and an
    /// upgrading user simply sees `attributionResult` as nil until their next
    /// install. Removed on construction so they do not sit in the plist forever.
    static let legacy = [
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
}
