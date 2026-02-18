import Foundation

extension WarpLink {

    /// Check for a deferred deep link on first launch.
    ///
    /// On first launch, collects device signals and queries the attribution API.
    /// On subsequent launches, returns the cached result without a network call.
    public static func checkDeferredDeepLink(
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        guard isConfigured else {
            completion(.failure(.notConfigured))
            return
        }

        let deps = lockedDeps()
        guard let store = deps.store,
              let collector = deps.collector,
              let client = deps.client else {
            completion(.failure(.notConfigured))
            return
        }

        if !store.isFirstLaunch {
            let cached = store.cachedAttribution
            deps.log?.log("Not first launch, returning cached attribution")
            DispatchQueue.main.async { completion(.success(cached)) }
            return
        }

        deps.log?.log("First launch — collecting device signals for attribution")
        let deviceId = collector.idfv
        collector.collectFingerprint { signalResult in
            switch signalResult {
            case .failure(let error):
                deps.log?.log("Signal collection failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
            case .success(let signals):
                performAttributionMatch(
                    signals: signals, client: client, store: store, log: deps.log,
                    deviceId: deviceId, completion: completion
                )
            }
        }
    }

    // MARK: - Private

    private struct Deps {
        let store: Storage?
        let collector: FingerprintCollector?
        let client: APIClient?
        let log: Logger?
    }

    private static func lockedDeps() -> Deps {
        lock.lock()
        let deps = Deps(
            store: storage,
            collector: fingerprintCollector,
            client: apiClient,
            log: logger
        )
        lock.unlock()
        return deps
    }

    private static func performAttributionMatch(
        signals: DeviceSignals,
        client: APIClient,
        store: Storage,
        log: Logger?,
        deviceId: String?,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        client.matchAttribution(
            signals: signals,
            sdkVersion: sdkVersion,
            deviceId: deviceId
        ) { result in
            switch result {
            case .failure(let error):
                log?.log("Attribution match failed: \(error.localizedDescription)")
                completion(.failure(error))
            case .success(let response):
                handleAttributionResponse(
                    response, store: store, log: log, completion: completion
                )
            }
        }
    }

    private static func handleAttributionResponse(
        _ response: AttributionResponse,
        store: Storage,
        log: Logger?,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        guard response.matched,
              let linkId = response.linkId,
              let destination = response.destinationUrl else {
            log?.log("No deferred deep link match")
            completion(.success(nil))
            return
        }

        let matchType = response.matchType.flatMap { MatchType(rawValue: $0) }
        let deepLink = WarpLinkDeepLink(
            linkId: linkId,
            destination: destination,
            deepLinkUrl: response.deepLinkUrl,
            customParams: response.customParams ?? [:],
            isDeferred: true,
            matchType: matchType,
            matchConfidence: response.matchConfidence
        )

        store.cachedAttribution = deepLink
        log?.log("Deferred deep link matched: \(linkId)")
        completion(.success(deepLink))
    }
}
