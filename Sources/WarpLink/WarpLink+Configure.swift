import Foundation

extension WarpLink {

    /// Configure the WarpLink SDK with your API key and optional settings.
    ///
    /// Call once, as early as possible (SwiftUI `App.init` or
    /// `application(_:didFinishLaunchingWithOptions:)`). With default options,
    /// the deferred deep link check runs automatically and results are routed
    /// to `options.onLink`.
    ///
    /// Calling it again with the same key and equal options changes nothing: the
    /// running session and its check carry on. A different key or different
    /// options start a new session and abandon the check in flight.
    public static func configure(
        apiKey: String,
        options: WarpLinkOptions? = nil
    ) {
        let resolvedOptions = options ?? WarpLinkOptions()

        guard validateApiKeyFormat(apiKey) else {
            reportInvalidKeyFormat(apiKey, options: resolvedOptions)
            return
        }
        if reuseLiveSession(apiKey: apiKey, options: resolvedOptions) { return }

        let newLogger = Logger(debugEnabled: resolvedOptions.debugLogging)
        let environment = KeyEnvironment(apiKey: apiKey)
        let newStorage = SDKEnvironment.makeStorage(environment)
        let newApiClient = APIClient(apiKey: apiKey, baseURL: resolvedOptions.apiEndpoint)

        let abandoned = installConfiguration(
            apiKey: apiKey, options: resolvedOptions, environment: environment,
            logger: newLogger, storage: newStorage, apiClient: newApiClient
        )

        abandoned.settle()
        // And the tap the reconfigure abandoned, which is cancelled too.
        supersedeInFlightTap()

        newLogger.log("Configured with API key: \(Logger.maskApiKey(apiKey))")
        newLogger.log("API endpoint: \(resolvedOptions.apiEndpoint)")

        performServerValidation(storage: newStorage, apiClient: newApiClient, logger: newLogger)

        if resolvedOptions.autoDeferredCheck {
            runAutoDeferredCheck()
        }
        resumePendingInvitation()
    }

    /// True when the live session already has this key and equal options. Only
    /// `onLink` is taken from the new options, so a new handler takes effect.
    private static func reuseLiveSession(apiKey: String, options: WarpLinkOptions) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard apiKey == WarpLink.apiKey, let live = WarpLink.options,
              live.isEquivalent(to: options) else { return false }
        WarpLink.options = options
        logger?.log("configure() called again with the same key and options, keeping the session")
        return true
    }

    /// Swaps in the state of a new key under one lock hold, referral stores
    /// included, so a concurrent `clearAttribution()` sees one key's stores or
    /// the other's, never a mix. Reconfiguring abandons any in-flight check; the
    /// caller answers its parked callers once this returns.
    private static func installConfiguration(
        apiKey: String,
        options: WarpLinkOptions,
        environment: KeyEnvironment,
        logger: Logger,
        storage newStorage: Storage,
        apiClient newApiClient: APIClient
    ) -> AbandonedDeferredCheck {
        // Resolved before the lock is taken: reading the declaration touches the
        // Info.plist, and none of it needs the SDK's own state.
        let declaredDomains = resolveLocalDomains(options: options)
        let cachedServerDomains = LinkDomainNormalizer.normalizeAll(newStorage.cachedDomains)

        lock.lock(); defer { lock.unlock() }
        self.apiKey = apiKey
        self.options = options
        self.logger = logger
        self.storage = newStorage
        self.apiClient = newApiClient
        self.fingerprintCollector = FingerprintCollector()
        self.apiKeyValidState = nil
        self.localDomains = declaredDomains
        self.serverDomains = cachedServerDomains
        self.lastHandledURLString = nil
        self.lastHandledURLAt = nil
        ReferralServices.use(environment)
        TetherServices.clearAll()
        return abandonDeferredCheckLocked()
    }
}
