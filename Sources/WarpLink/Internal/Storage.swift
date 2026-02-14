import Foundation

/// UserDefaults wrapper for persisting SDK state.
class Storage {

    private static let firstLaunchKey = "warplink_first_launch"
    private static let apiKeyValidatedAtKey = "warplink_api_key_validated_at"
    private static let hasCachedAttrKey = "warplink_has_cached_attribution"
    private static let cachedLinkIdKey = "warplink_cached_link_id"
    private static let cachedDestKey = "warplink_cached_destination"
    private static let cachedDeepLinkUrlKey = "warplink_cached_deep_link_url"
    private static let cachedIsDeferredKey = "warplink_cached_is_deferred"
    private static let cachedMatchTypeKey = "warplink_cached_match_type"
    private static let cachedMatchConfKey = "warplink_cached_match_confidence"
    private static let cachedCustomParamsKey = "warplink_cached_custom_params"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether this is the first launch of the app (no prior SDK interaction).
    var isFirstLaunch: Bool {
        if defaults.object(forKey: Self.firstLaunchKey) == nil {
            defaults.set(false, forKey: Self.firstLaunchKey)
            return true
        }
        return false
    }

    /// Timestamp of the last successful API key validation.
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

    /// Whether the API key validation cache is still valid (within 24 hours).
    var isApiKeyValidationCacheValid: Bool {
        guard let validatedAt = apiKeyValidatedAt else { return false }
        return Date().timeIntervalSince(validatedAt) < 86400
    }

    /// Cached attribution result from the last deferred deep link check.
    var cachedAttribution: WarpLinkDeepLink? {
        get { return readCachedAttribution() }
        set { writeCachedAttribution(newValue) }
    }

    /// Clear all stored SDK data. Used for testing.
    func clearAll() {
        defaults.removeObject(forKey: Self.firstLaunchKey)
        defaults.removeObject(forKey: Self.apiKeyValidatedAtKey)
        removeCachedAttributionKeys()
    }

    // MARK: - Private

    private func readCachedAttribution() -> WarpLinkDeepLink? {
        guard defaults.bool(forKey: Self.hasCachedAttrKey) else {
            return nil
        }
        guard let linkId = defaults.string(forKey: Self.cachedLinkIdKey),
              let destination = defaults.string(forKey: Self.cachedDestKey) else {
            return nil
        }

        let deepLinkUrl = defaults.string(forKey: Self.cachedDeepLinkUrlKey)
        let isDeferred = defaults.bool(forKey: Self.cachedIsDeferredKey)
        let matchType = defaults.string(forKey: Self.cachedMatchTypeKey)
            .flatMap { MatchType(rawValue: $0) }
        let matchConfidence: Double? = defaults.object(forKey: Self.cachedMatchConfKey) != nil
            ? defaults.double(forKey: Self.cachedMatchConfKey)
            : nil
        let customParams = readCustomParams()

        return WarpLinkDeepLink(
            linkId: linkId,
            destination: destination,
            deepLinkUrl: deepLinkUrl,
            customParams: customParams,
            isDeferred: isDeferred,
            matchType: matchType,
            matchConfidence: matchConfidence
        )
    }

    private func writeCachedAttribution(_ deepLink: WarpLinkDeepLink?) {
        guard let deepLink = deepLink else {
            removeCachedAttributionKeys()
            return
        }

        defaults.set(true, forKey: Self.hasCachedAttrKey)
        defaults.set(deepLink.linkId, forKey: Self.cachedLinkIdKey)
        defaults.set(deepLink.destination, forKey: Self.cachedDestKey)
        defaults.set(deepLink.deepLinkUrl, forKey: Self.cachedDeepLinkUrlKey)
        defaults.set(deepLink.isDeferred, forKey: Self.cachedIsDeferredKey)

        if let matchType = deepLink.matchType {
            defaults.set(matchType.rawValue, forKey: Self.cachedMatchTypeKey)
        } else {
            defaults.removeObject(forKey: Self.cachedMatchTypeKey)
        }

        if let confidence = deepLink.matchConfidence {
            defaults.set(confidence, forKey: Self.cachedMatchConfKey)
        } else {
            defaults.removeObject(forKey: Self.cachedMatchConfKey)
        }

        writeCustomParams(deepLink.customParams)
    }

    private func readCustomParams() -> [String: Any] {
        guard let data = defaults.data(forKey: Self.cachedCustomParamsKey) else {
            return [:]
        }
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return obj ?? [:]
    }

    private func writeCustomParams(_ params: [String: Any]) {
        if params.isEmpty {
            defaults.removeObject(forKey: Self.cachedCustomParamsKey)
            return
        }
        if let data = try? JSONSerialization.data(withJSONObject: params) {
            defaults.set(data, forKey: Self.cachedCustomParamsKey)
        }
    }

    private func removeCachedAttributionKeys() {
        defaults.removeObject(forKey: Self.hasCachedAttrKey)
        defaults.removeObject(forKey: Self.cachedLinkIdKey)
        defaults.removeObject(forKey: Self.cachedDestKey)
        defaults.removeObject(forKey: Self.cachedDeepLinkUrlKey)
        defaults.removeObject(forKey: Self.cachedIsDeferredKey)
        defaults.removeObject(forKey: Self.cachedMatchTypeKey)
        defaults.removeObject(forKey: Self.cachedMatchConfKey)
        defaults.removeObject(forKey: Self.cachedCustomParamsKey)
    }
}
