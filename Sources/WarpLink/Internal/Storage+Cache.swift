import Foundation

/// The caches that describe the key and the last match, not the install gate.
extension Storage {

    // MARK: - API key validation cache

    var apiKeyValidatedAt: Date? {
        get {
            let interval = defaults.double(forKey: keys.apiKeyValidatedAt)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let date = newValue {
                defaults.set(date.timeIntervalSince1970, forKey: keys.apiKeyValidatedAt)
            } else {
                defaults.removeObject(forKey: keys.apiKeyValidatedAt)
            }
        }
    }

    var isApiKeyValidationCacheValid: Bool {
        guard let validatedAt = apiKeyValidatedAt else { return false }
        return Date().timeIntervalSince(validatedAt) < 86400
    }

    // MARK: - Cached link domains (from /sdk/validate)

    var cachedDomains: [String] {
        get { defaults.stringArray(forKey: keys.domains) ?? [] }
        set { defaults.set(newValue, forKey: keys.domains) }
    }

    // MARK: - What onLink was given

    /// The route identity of the last attribution link `onLink` received, or
    /// nil when it received none. It survives launches and is forgotten with
    /// the attribution.
    var onLinkDeliveredRoute: String? {
        deliveryLock.lock(); defer { deliveryLock.unlock() }
        return defaults.string(forKey: keys.onLinkDelivered)
    }

    /// Bumps the clear generation and drops the delivered-link record in one
    /// hold of the delivery lock, so a dispatch that read an older generation
    /// can neither write the record back nor reach `onLink`. Every clear calls it.
    func forgetOnLinkDelivery() {
        deliveryLock.lock(); defer { deliveryLock.unlock() }
        clearGeneration += 1
        defaults.removeObject(forKey: keys.onLinkDelivered)
    }

    /// Counts the clears of this attribution state. Read it when a link is found.
    var attributionClearGeneration: Int {
        deliveryLock.lock(); defer { deliveryLock.unlock() }
        return clearGeneration
    }

    /// Records the link `onLink` is about to get, unless a clear came after
    /// `generation` was read. The check and the write are one step.
    func recordOnLinkDelivery(_ route: String, ifGeneration generation: Int) -> Bool {
        deliveryLock.lock(); defer { deliveryLock.unlock() }
        guard generation == clearGeneration else { return false }
        defaults.set(route, forKey: keys.onLinkDelivered)
        installMarkerStore.clear(keys.awaitingDelivery)
        return true
    }

    /// The link the gate saved that `onLink` has not received, if any.
    var awaitingDeliveryRoute: String? {
        installMarkerStore.value(keys.awaitingDelivery)
    }

    func clearAwaitingDelivery() {
        deliveryLock.lock(); defer { deliveryLock.unlock() }
        installMarkerStore.clear(keys.awaitingDelivery)
    }

    func markAwaitingDelivery(_ route: String) {
        installMarkerStore.write(keys.awaitingDelivery, value: route)
    }

    /// True while no clear has come since `generation` was read.
    func isCurrentAttributionGeneration(_ generation: Int) -> Bool {
        deliveryLock.lock(); defer { deliveryLock.unlock() }
        return generation == clearGeneration
    }

    // MARK: - Cached attribution payload

    var cachedAttribution: WarpLinkDeepLink? {
        get {
            guard let data = defaults.data(forKey: keys.cachedAttribution) else { return nil }
            return try? JSONDecoder().decode(WarpLinkDeepLink.self, from: data)
        }
        set {
            if let value = newValue, let data = try? JSONEncoder().encode(value) {
                defaults.set(data, forKey: keys.cachedAttribution)
            } else {
                defaults.removeObject(forKey: keys.cachedAttribution)
            }
        }
    }
}
