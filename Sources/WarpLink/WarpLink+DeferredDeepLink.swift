import Foundation

extension WarpLink {

    /// Check for a deferred deep link on first launch.
    ///
    /// Runs the attribution match until it definitively completes; after that,
    /// returns the cached result without a network call for the rest of this
    /// install. A failed attempt (e.g. offline) is NOT treated as complete, so
    /// the next launch retries. A reinstall starts over and is reported with
    /// `is_reinstall`, because a reinstall counts as an install.
    ///
    /// With `autoDeferredCheck` on (default), `configure()` calls this for you
    /// and routes the result to `onLink`.
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

        if answeredFromCache(store: store, log: deps.log, completion: completion) { return }

        // Collapse concurrent checks (the auto-fire from configure() racing a
        // manual call, or repeated manual calls) into a single
        // /attribution/match, mirroring Android's deferredCheckInFlight guard.
        // A caller that loses the race is parked and receives the in-flight
        // check's result rather than a possibly-empty cache.
        guard let generation = claimDeferredCheck(parking: completion) else {
            deps.log?.log("Deferred check already in flight, awaiting its result")
            return
        }

        let retrying = store.hasAttemptedAttribution
        store.hasAttemptedAttribution = true
        // Read before the request, not inside the response handler: the gate is
        // closed by the response itself, so reading it afterwards would report
        // every reinstall as a first install.
        let isReinstall = store.isReinstall
        logCheckStart(retrying: retrying, isReinstall: isReinstall, log: deps.log)

        performAttributionMatch(
            signals: collector.collect(), client: client, store: store,
            log: deps.log, deviceId: collector.idfv,
            isReinstall: isReinstall, generation: generation
        ) { result in
            let parked = endDeferredCheck(generation: generation)
            completion(result)
            parked.forEach { pending in SDKEnvironment.deliver { pending(result) } }
        }
    }

    /// Completions parked while a deferred check is in flight. Drained by
    /// `endDeferredCheck(generation:)` so every caller sees the same result.
    /// Non-private so `reset()` can clear it alongside `deferredCheckInFlight`.
    static var parkedDeferredCompletions:
        [(Result<WarpLinkDeepLink?, WarpLinkError>) -> Void] = []

    /// Atomically claim the deferred check, returning the generation it runs in;
    /// parks `completion` and returns nil if one is already in flight.
    private static func claimDeferredCheck(
        parking completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) -> Int? {
        lock.lock(); defer { lock.unlock() }
        if deferredCheckInFlight {
            parkedDeferredCompletions.append(completion)
            return nil
        }
        deferredCheckInFlight = true
        return deferredCheckGeneration
    }

    /// Release the in-flight claim and hand back the parked completions.
    ///
    /// A check abandoned by a reconfigure runs in an older generation (and
    /// `configure()` already answered its parked callers), so it must not
    /// release its successor's claim or drain that successor's parked callers.
    private static func endDeferredCheck(
        generation: Int
    ) -> [(Result<WarpLinkDeepLink?, WarpLinkError>) -> Void] {
        lock.lock(); defer { lock.unlock() }
        guard generation == deferredCheckGeneration else { return [] }
        deferredCheckInFlight = false
        let parked = parkedDeferredCompletions
        parkedDeferredCompletions = []
        return parked
    }

    /// Internal: auto-fired from `configure()` when `autoDeferredCheck` is on.
    /// Dispatches to `onLink` only while attribution is still pending, so a
    /// completed deferred result is delivered at most once (never re-fired on
    /// every subsequent launch).
    ///
    /// Runs even without an `onLink` sink: a bare `configure(apiKey:)` is
    /// documented to make attribution work automatically, and the match is
    /// recorded server-side and cached locally whether or not a sink exists to
    /// route it. A manual `checkDeferredDeepLink(completion:)` that races this
    /// one is parked and receives the same result.
    static func runAutoDeferredCheck() {
        lock.lock(); let store = storage; lock.unlock()
        guard let store = store, !store.isAttributionComplete else { return }
        checkDeferredDeepLink { result in
            dispatchToOnLink(result)
        }
    }

    // MARK: - Private

    private struct Deps {
        let store: Storage?
        let collector: FingerprintCollector?
        let client: APIClient?
        let log: Logger?
    }

    /// Answer from the cache when attribution has already completed for this
    /// install, and report whether it did. Scoped to the install, so a reinstall
    /// falls through to a real check instead of replaying the old result.
    private static func answeredFromCache(
        store: Storage,
        log: Logger?,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) -> Bool {
        guard store.isAttributionComplete else { return false }
        let cached = store.cachedAttribution
        log?.log("Attribution already complete for this install, returning cached result")
        SDKEnvironment.deliver { completion(.success(cached)) }
        return true
    }

    /// One line saying why this check is running, for hosts with debug logging.
    private static func logCheckStart(retrying: Bool, isReinstall: Bool, log: Logger?) {
        if retrying {
            log?.log("Retrying deferred attribution (prior attempt did not complete)")
            return
        }
        log?.log(
            isReinstall
                ? "Reinstall: this device was attributed under an earlier install"
                : "First launch: collecting device signals for attribution"
        )
    }

    private static func lockedDeps() -> Deps {
        lock.lock(); defer { lock.unlock() }
        return Deps(store: storage, collector: fingerprintCollector, client: apiClient, log: logger)
    }
}
