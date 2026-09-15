import Foundation

/// API key validation: the local format check, and the server round trip fired
/// once per `configure()`.
///
/// The server's answer carries a second payload beyond the verdict: the org's
/// verified link domains. That half is a supplement, not the source of truth.
/// It lands whenever the network answers, which can be long after the first
/// link has already had to be accepted or rejected, so the domains a developer
/// declares locally stand on their own (see `WarpLink+Domains`).
extension WarpLink {

    /// The local format check, run before anything is stored: a key that cannot
    /// be right is not worth a network round trip.
    static func validateApiKeyFormat(_ key: String) -> Bool {
        key.range(of: "^wl_(live|test)_[a-zA-Z0-9]{32}$", options: .regularExpression) != nil
    }

    /// Cross-SDK parity (WL-S11): all three SDKs surface a malformed key to
    /// `onLink` and always warn, rather than throwing, so a typo'd key is never
    /// silently swallowed. The SDK stays unconfigured.
    static func reportInvalidKeyFormat(
        _ key: String,
        options: WarpLinkOptions,
        logger: Logger? = nil
    ) {
        (logger ?? Logger(debugEnabled: options.debugLogging))
            .warn("Invalid API key format: \(Logger.maskApiKey(key))")
        guard let sink = options.onLink else { return }
        SDKEnvironment.deliver { sink(.failure(.invalidApiKeyFormat)) }
    }

    static func performServerValidation(
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
            handleValidationResult(result, storage: storage, apiClient: apiClient, logger: logger)
        }
    }

    static func handleValidationResult(
        _ result: Result<ValidationResult, WarpLinkError>,
        storage: Storage,
        apiClient: APIClient,
        logger: Logger
    ) {
        switch result {
        case let .success(validation) where validation.valid:
            lock.lock()
            apiKeyValidState = true
            storage.apiKeyValidatedAt = Date()
            lock.unlock()
            // Outside the lock: `applyServerDomains` takes it, and `lock` is a
            // plain NSLock, so nesting the two would deadlock.
            applyServerDomains(validation.domains, storage: storage)
            logger.log("API key validated successfully")
        case .success:
            lock.lock(); apiKeyValidState = false; lock.unlock()
            logger.warn(
                "API key rejected by server (invalid or revoked). "
                + "Deep linking and attribution will not work until a valid key is supplied."
            )
        case let .failure(error):
            logger.log("API key validation error: \(error.localizedDescription)")
        }
    }
}
