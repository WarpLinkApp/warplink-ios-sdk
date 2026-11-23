import Foundation

extension WarpLink {

    /// Check for a deferred deep link on first launch.
    ///
    /// Runs the attribution match until it definitively completes; after that,
    /// returns the cached result without a network call for the rest of this
    /// install. A failed attempt (e.g. offline) is NOT treated as complete, so a
    /// later check retries, once a wait that grows with each failure has passed,
    /// and stops when the server's give-up time has passed. A reinstall starts over and is
    /// reported with `is_reinstall`, because a reinstall counts as an install.
    ///
    /// No request is made, and the result is "no match", when the install is
    /// older than the server's limit or a failed check is still being waited
    /// out. The check starts only while the app is in the foreground: a call
    /// made earlier waits until the app is active. A check counts as failed
    /// when its request is sent, so a process that ends meanwhile still makes
    /// the next check wait.
    ///
    /// With `autoDeferredCheck` on (default), `configure()` calls this for you
    /// and routes the result to `onLink`.
    public static func checkDeferredDeepLink(
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        runDeferredCheck(routesToOnLink: false) { result in
            // The app has the link now, so a later launch must not hand it to
            // `onLink` again.
            if case .success(_?) = result { storage?.clearAwaitingDelivery() }
            completion(result)
        }
    }

    /// `routesToOnLink` is true only for the check `configure()` starts: its
    /// result goes to `onLink`, so a link it finds is marked as awaiting delivery.
    static func runDeferredCheck(
        routesToOnLink: Bool,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        guard isConfigured, let deps = DeferredCheckDeps.current() else {
            completion(.failure(.notConfigured))
            return
        }

        if answeredFromCache(store: deps.store, log: deps.log, completion: completion) { return }

        // Only a skip is logged here. A check that goes on is decided, and
        // logged, again once the app is in the foreground: a call made in the
        // background can wait a long time.
        let reading = readCheckGate(store: deps.store, environment: deps.environment)
        guard case .send = reading.gate else {
            recordCheckGate(reading, store: deps.store, log: deps.log)
            logCheckOutcome()
            SDKEnvironment.deliver { completion(.success(nil)) }
            return
        }

        // Collapse concurrent checks (the auto-fire from configure() racing a
        // manual call, or repeated manual calls) into a single
        // /attribution/match, mirroring Android's deferredCheckInFlight guard.
        // A caller that loses the race is parked and receives the in-flight
        // check's result rather than a possibly-empty cache.
        guard let generation = claimDeferredCheck(parking: completion, routesToOnLink: routesToOnLink) else {
            deps.log?.log("Deferred check already in flight, awaiting its result")
            return
        }

        SDKEnvironment.whenActive {
            startDeferredCheck(deps, generation: generation, completion: completion)
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
        parking completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void,
        routesToOnLink: Bool
    ) -> Int? {
        lock.lock(); defer { lock.unlock() }
        if deferredCheckInFlight {
            parkedDeferredCompletions.append(completion)
            if routesToOnLink { onLinkRoutedGeneration = deferredCheckGeneration }
            return nil
        }
        deferredCheckInFlight = true
        onLinkRoutedGeneration = routesToOnLink ? deferredCheckGeneration : nil
        return deferredCheckGeneration
    }

    /// Release the in-flight claim and hand back the parked completions.
    ///
    /// A check abandoned by a reconfigure runs in an older generation (and
    /// `configure()` already answered its parked callers), so it must not
    /// release its successor's claim or drain that successor's parked callers.
    static func endDeferredCheck(
        generation: Int
    ) -> [(Result<WarpLinkDeepLink?, WarpLinkError>) -> Void] {
        lock.lock(); defer { lock.unlock() }
        guard generation == deferredCheckGeneration else { return [] }
        deferredCheckInFlight = false
        onLinkRoutedGeneration = nil
        let parked = parkedDeferredCompletions
        parkedDeferredCompletions = []
        return parked
    }

    /// The gate is saved on the network queue, before the hop to the main queue
    /// that hands the link to `onLink`. A process that ended in between left a
    /// closed gate and a link `onLink` never got. The gate's save also wrote an
    /// awaiting-delivery marker, which delivery clears. Hand the link over only
    /// while that marker names it: an install from before the marker has none.
    private static func redeliverUnroutedLink(store: Storage, generation: Int) {
        guard let link = store.cachedAttribution,
              store.awaitingDeliveryRoute == link.routeIdentity else { return }
        dispatchAttributionToOnLink(.success(link), ifGeneration: generation)
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
        guard let store = store else { return }
        // Read before the check starts, so a clear at any point after that wins
        // over the link the check finds.
        let generation = store.attributionClearGeneration
        guard !store.isAttributionComplete else {
            redeliverUnroutedLink(store: store, generation: generation)
            return
        }
        runDeferredCheck(routesToOnLink: true) { result in
            dispatchAttributionToOnLink(result, ifGeneration: generation)
        }
    }
}
