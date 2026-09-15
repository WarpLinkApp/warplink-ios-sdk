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

    static let defaultDomain = "aplnk.to"
    static let dedupeWindow: TimeInterval = 1.0

    /// The current SDK version.
    public static let sdkVersion = "1.1.0"

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

    /// Configure the WarpLink SDK with your API key and optional settings.
    ///
    /// Call once, as early as possible (SwiftUI `App.init` or
    /// `application(_:didFinishLaunchingWithOptions:)`). With default options,
    /// the deferred deep link check runs automatically and results are routed
    /// to `options.onLink`.
    public static func configure(
        apiKey: String,
        options: WarpLinkOptions? = nil
    ) {
        let resolvedOptions = options ?? WarpLinkOptions()

        guard validateApiKeyFormat(apiKey) else {
            reportInvalidKeyFormat(apiKey, options: resolvedOptions)
            return
        }

        let newLogger = Logger(debugEnabled: resolvedOptions.debugLogging)
        let newStorage = Storage()
        let newApiClient = APIClient(apiKey: apiKey, baseURL: resolvedOptions.apiEndpoint)
        let newCollector = FingerprintCollector()
        // Resolved before the lock is taken: reading the declaration touches the
        // Info.plist, and none of it needs the SDK's own state.
        let declaredDomains = resolveLocalDomains(options: resolvedOptions)
        let cachedServerDomains = LinkDomainNormalizer.normalizeAll(newStorage.cachedDomains)

        lock.lock()
        self.apiKey = apiKey
        self.options = resolvedOptions
        self.logger = newLogger
        self.storage = newStorage
        self.apiClient = newApiClient
        self.fingerprintCollector = newCollector
        self.apiKeyValidState = nil
        self.localDomains = declaredDomains
        self.serverDomains = cachedServerDomains
        self.lastHandledURLString = nil
        self.lastHandledURLAt = nil
        self.deferredCheckInFlight = false
        self.deferredCheckGeneration += 1
        // Reconfiguring abandons any in-flight check, so callers parked on it
        // must be answered here. Leaving them queued would let the abandoned
        // check deliver its result to callers that parked on a later one.
        let abandoned = parkedDeferredCompletions
        parkedDeferredCompletions = []
        // Taken here, cancelled below the unlock: cancelling calls the
        // completion, which takes this lock itself.
        let abandonedCheck = takeAbandonedDeferredCheckLocked()
        lock.unlock()

        answerAbandonedCallers(abandoned)
        abandonedCheck?.cancel()
        // And the tap the reconfigure abandoned, which is cancelled too.
        supersedeInFlightTap()

        newLogger.log("Configured with API key: \(Logger.maskApiKey(apiKey))")
        newLogger.log("API endpoint: \(resolvedOptions.apiEndpoint)")

        performServerValidation(storage: newStorage, apiClient: newApiClient, logger: newLogger)

        if resolvedOptions.autoDeferredCheck {
            runAutoDeferredCheck()
        }
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
        deferredCheckInFlight = false
        deferredCheckGeneration += 1
        parkedDeferredCompletions = []
        let abandonedCheck = takeAbandonedDeferredCheckLocked()
        lock.unlock()

        abandonedCheck?.cancel()
        supersedeInFlightTap()
    }

    // MARK: - Internal

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

    // MARK: - Private

    /// Answer the callers a reconfigure stranded on the check it just abandoned.
    ///
    /// They get the `.success(nil)` no-op rather than a fabricated
    /// `.notConfigured` (the SDK is configured), so an auto check parked on the
    /// abandoned one stays silent to `onLink`, which suppresses a no-match.
    /// Parity with the abandoned check's own response path.
    private static func answerAbandonedCallers(
        _ abandoned: [(Result<WarpLinkDeepLink?, WarpLinkError>) -> Void]
    ) {
        abandoned.forEach { pending in
            SDKEnvironment.deliver { pending(.success(nil)) }
        }
    }
}
