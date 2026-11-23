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
    /// The identity of the last attribution link handed to `onLink`. Written when
    /// `onLink` is called, so it records delivery and not just a match.
    let onLinkDelivered: String
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
    /// The installation id, in the install marker store so a restore does not
    /// bring it back.
    let installationId: String
    /// How many launches of this install sent a deferred check, in the install
    /// marker store.
    let attemptNumber: String
    /// The failed checks of this install (`CheckBackoff.encoded`), in the
    /// install marker store.
    let checkBackoff: String
    /// The note that a check was skipped because the install is too old, in the
    /// install marker store. Never the gate.
    let skippedForAge: String
    /// The route identity of a link the gate saved that `onLink` has not yet
    /// received, in the install marker store. Absent for any install that saved
    /// its link before this marker existed, so an upgrade never redelivers.
    let awaitingDelivery: String
    /// The server's last `sdk_policy`. It describes the key, not the install.
    let sdkPolicy: String

    init(environment: KeyEnvironment = .production) {
        apiKeyValidatedAt = environment.scoped("warplink_api_key_validated_at")
        attemptedMarker = environment.scoped("warplink_attribution_attempted")
        cachedAttribution = environment.scoped("warplink_cached_attribution")
        onLinkDelivered = environment.scoped("warplink_onlink_delivered")
        domains = environment.scoped("warplink_cached_domains")
        installCompleteMarker = environment.scoped("warplink_attribution_complete")
        deviceSeenMarker = environment.scoped("warplink_attribution_complete")
        installCompleteFallback = environment.scoped("warplink_attribution_complete_fallback")
        installationId = environment.scoped("warplink_installation_id")
        attemptNumber = environment.scoped("warplink_attempt_number")
        checkBackoff = environment.scoped("warplink_check_backoff")
        skippedForAge = environment.scoped("warplink_skipped_for_age")
        awaitingDelivery = environment.scoped("warplink_awaiting_delivery")
        sdkPolicy = environment.scoped("warplink_sdk_policy")
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
