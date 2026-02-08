import Foundation

/// Main entry point for the WarpLink deep linking SDK.
public final class WarpLink {

    static let lock = NSLock()
    private static var apiKey: String?
    private static var options: WarpLinkOptions?
    static var logger: Logger?
    static var apiClient: APIClient?
    static var storage: Storage?
    static var fingerprintCollector: FingerprintCollector?
    private static var isApiKeyValid: Bool?

    /// The current SDK version.
    public static let sdkVersion = "0.1.0"

    /// Whether the SDK has been configured via `configure(apiKey:options:)`.
    public static var isConfigured: Bool {
        lock.lock()
        defer { lock.unlock() }
        return apiKey != nil
    }

    /// The cached attribution result from the last deferred deep link check, or `nil` if none.
    public static var attributionResult: WarpLinkDeepLink? {
        lock.lock()
        defer { lock.unlock() }
        return storage?.cachedAttribution
    }

    /// Configure the WarpLink SDK with your API key and optional settings.
    ///
    /// Must be called before any other SDK methods. Typically called in
    /// `application(_:didFinishLaunchingWithOptions:)` or the SwiftUI `App` init.
    ///
    /// - Parameters:
    ///   - apiKey: Your WarpLink API key (e.g., `wl_live_xxx`).
    ///   - options: Optional configuration overrides.
    public static func configure(
        apiKey: String,
        options: WarpLinkOptions? = nil
    ) {
        let resolvedOptions = options ?? WarpLinkOptions()

        guard validateApiKeyFormat(apiKey) else {
            if resolvedOptions.debugLogging {
                let tempLogger = Logger(debugEnabled: true)
                tempLogger.log("Invalid API key format: \(Logger.maskApiKey(apiKey))")
            }
            return
        }

        let newLogger = Logger(debugEnabled: resolvedOptions.debugLogging)
        let newStorage = Storage()
        let newApiClient = APIClient(apiKey: apiKey, baseURL: resolvedOptions.apiEndpoint)
        let newFingerprintCollector = FingerprintCollector()

        lock.lock()
        self.apiKey = apiKey
        self.options = resolvedOptions
        self.logger = newLogger
        self.storage = newStorage
        self.apiClient = newApiClient
        self.fingerprintCollector = newFingerprintCollector
        self.isApiKeyValid = nil
        lock.unlock()

        newLogger.log("Configured with API key: \(Logger.maskApiKey(apiKey))")
        newLogger.log("API endpoint: \(resolvedOptions.apiEndpoint)")
        newLogger.log("Match window: \(resolvedOptions.matchWindowHours) hours")

        performServerValidation(storage: newStorage, apiClient: newApiClient, logger: newLogger)
    }

    /// Handle an incoming Universal Link URL and resolve it to a deep link.
    public static func handleDeepLink(
        _ url: URL,
        completion: @escaping (Result<WarpLinkDeepLink, WarpLinkError>) -> Void
    ) {
        guard isConfigured else {
            completion(.failure(.notConfigured))
            return
        }

        guard url.isWarpLinkUniversalLink else {
            DispatchQueue.main.async { completion(.failure(.invalidURL)) }
            return
        }

        guard let slug = url.warpLinkSlug else {
            DispatchQueue.main.async { completion(.failure(.invalidURL)) }
            return
        }

        let domain = url.host ?? "aplnk.to"

        lock.lock()
        let client = apiClient
        let log = logger
        lock.unlock()

        guard let client = client else {
            DispatchQueue.main.async { completion(.failure(.notConfigured)) }
            return
        }

        log?.log("Resolving Universal Link: \(url.absoluteString)")

        client.resolveLink(slug: slug, domain: domain) { result in
            // resolveLink dispatches to main thread, so we're already on main here
            switch result {
            case .success(let response):
                let deepLink = WarpLinkDeepLink(
                    linkId: response.id,
                    destination: response.destinationUrl,
                    deepLinkUrl: response.iosUrl,
                    customParams: response.customParams,
                    isDeferred: false,
                    matchType: .deterministic,
                    matchConfidence: 1.0
                )
                log?.log("Resolved link: \(response.slug) → \(response.destinationUrl)")
                completion(.success(deepLink))
            case .failure(let error):
                log?.log("Failed to resolve link: \(error.localizedDescription)")
                completion(.failure(error))
            }
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
        isApiKeyValid = nil
        lock.unlock()
    }

    // MARK: - Private

    private static func validateApiKeyFormat(_ key: String) -> Bool {
        let pattern = "^wl_(live|test)_[a-zA-Z0-9]{32}$"
        return key.range(of: pattern, options: .regularExpression) != nil
    }

    private static func performServerValidation(
        storage: Storage,
        apiClient: APIClient,
        logger: Logger
    ) {
        if storage.isApiKeyValidationCacheValid {
            logger.log("API key validation cached, skipping")
            return
        }

        logger.log("Validating API key...")
        apiClient.validateApiKey { result in
            lock.lock()
            switch result {
            case .success(true):
                isApiKeyValid = true
                storage.apiKeyValidatedAt = Date()
                lock.unlock()
                logger.log("API key validated successfully")
            case .success(false):
                isApiKeyValid = false
                lock.unlock()
                logger.log("API key validation failed: key rejected by server")
            case .failure(let error):
                lock.unlock()
                logger.log("API key validation error: \(error.localizedDescription)")
            }
        }
    }
}
