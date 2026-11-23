import Foundation

/// Main entry point for the WarpLink deep linking SDK.
///
/// Opt-out by default: `configure(apiKey:options:)` with a `WarpLinkOptions.onLink`
/// handler makes deep linking, deferred deep linking, and attribution work
/// automatically. Deliver incoming
/// Universal Links with `WarpLink.continue(_:)` / `WarpLink.open(_:)` or the
/// provided `WarpLinkAppDelegate` / `WarpLinkSceneDelegate`. No swizzling.
public final class WarpLink {

    static let lock = NSLock()
    static var apiKey: String?
    static var options: WarpLinkOptions?
    static var logger: Logger?
    static var apiClient: APIClient?
    static var storage: Storage?
    static var fingerprintCollector: FingerprintCollector?

    static var apiKeyValidState: Bool?
    // Not private: `releaseDuplicateClaim` drops the claim beside the failure
    // branch that causes it, which lives in the resolve extension.
    static var lastHandledURLString: String?
    static var lastHandledURLAt: TimeInterval?

    /// Monotonic seconds for the dedupe window. Deliberately NOT `Date()`:
    /// wall clock moves backwards when NTP corrects a drifted device or the
    /// user edits the date, and a backward step makes the elapsed subtraction
    /// negative, which a bare `<` reads as "inside the window". Every repeat
    /// tap on a link is then dropped until the clock catches up.
    ///
    /// `systemUptime` cannot run backwards. Injectable so a test can drive the
    /// backward step this exists to survive. Restored by `reset()`.
    static var monotonicNow: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// Guards a deferred attribution check so an auto-fire from `configure()`
    /// racing a manual `checkDeferredDeepLink(completion:)` collapses into one
    /// `/attribution/match` (parity with Android's `deferredCheckInFlight`).
    static var deferredCheckInFlight = false
    /// Bumped whenever `configure()`/`reset()` abandons an in-flight check, so
    /// the abandoned check can tell it is stale and leave its successor's
    /// in-flight claim and parked callers alone.
    static var deferredCheckGeneration = 0
    /// The generation of the running check whose result goes to `onLink`, or nil
    /// when only a manual caller waits for it. Decides whether the gate writes
    /// the awaiting-delivery marker. A newer generation makes it stale.
    static var onLinkRoutedGeneration: Int?

    /// The failure the running check counted when it sent, held so a reconfigure
    /// can give it back. Guarded by `lock`.
    static var countedCheck: CountedCheck?

    static let defaultDomain = "aplnk.to"
    static let dedupeWindow: TimeInterval = 1.0

    /// The current SDK version.
    public static let sdkVersion = "1.4.1"

    /// Whether the SDK has been configured via `configure(apiKey:options:)`.
    public static var isConfigured: Bool {
        lock.lock(); defer { lock.unlock() }
        return apiKey != nil
    }

    /// The server's API-key validation verdict: `true` (valid), `false`
    /// (rejected/revoked), or `nil` (not yet determined). Surfaced so hosts
    /// can react to a misconfigured key; the SDK also logs a warning.
    public static var isApiKeyValid: Bool? {
        lock.lock(); defer { lock.unlock() }
        return apiKeyValidState
    }

    /// The cached attribution result from the last deferred deep link check.
    public static var attributionResult: WarpLinkDeepLink? {
        lock.lock(); defer { lock.unlock() }
        return storage?.cachedAttribution
    }

    /// Whether the deferred attribution check has definitively completed for
    /// this install. It is scoped to the install, not to the device: a reinstall
    /// starts over, because a reinstall counts as an install. The React Native
    /// bridge reads this so a deferred match is dispatched to `onLink` at most
    /// once across launches, matching the native auto-dispatch guard.
    public static var isAttributionComplete: Bool {
        lock.lock(); defer { lock.unlock() }
        return storage?.isAttributionComplete ?? false
    }

    /// Reset SDK state. Internal method for testing only.
    static func reset() {
        lock.lock()
        apiKey = nil
        options = nil
        logger = nil
        apiClient = nil
        storage = nil
        fingerprintCollector = nil
        apiKeyValidState = nil
        localDomains = [WarpLink.defaultDomain]
        serverDomains = []
        // Restored too, so a test that injects a declaration cannot leak it
        // into the next one.
        domainDeclarationSource = Bundle.main
        lastHandledURLString = nil
        lastHandledURLAt = nil
        monotonicNow = { ProcessInfo.processInfo.systemUptime }
        // Same reason as the clock above: a test that closed the network or the
        // delivery hop must not leak that into the next one.
        SDKEnvironment.reset()
        ReferralServices.reset()
        TetherServices.reset()
        deferredCheckInFlight = false
        onLinkRoutedGeneration = nil
        deferredCheckGeneration += 1
        countedCheck = nil
        parkedDeferredCompletions = []
        let abandonedCheck = takeAbandonedDeferredCheckLocked()
        lock.unlock()
        PendingForegroundRetry.disarm()

        abandonedCheck?.cancel()
        supersedeInFlightTap()
    }
}
