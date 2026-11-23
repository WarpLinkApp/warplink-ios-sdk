import Foundation

/// What a deferred check reads from the configured SDK, taken in one lock hold.
struct DeferredCheckDeps {
    let store: Storage
    let collector: FingerprintCollector
    let client: APIClient
    let environment: KeyEnvironment
    let log: Logger?

    /// Nil before `configure()`.
    static func current() -> DeferredCheckDeps? {
        WarpLink.lock.lock(); defer { WarpLink.lock.unlock() }
        guard let store = WarpLink.storage, let collector = WarpLink.fingerprintCollector,
              let client = WarpLink.apiClient, let key = WarpLink.apiKey else { return nil }
        return DeferredCheckDeps(
            store: store, collector: collector, client: client,
            environment: KeyEnvironment(apiKey: key), log: WarpLink.logger
        )
    }
}

extension WarpLink {

    /// Starts a claimed check once the app is in the foreground.
    ///
    /// The check may have waited a long time for the foreground. A reconfigure
    /// may have abandoned it meanwhile, and the install may have grown too old
    /// or a failure may now be waited out, so the gate is decided again here.
    /// Either answers with the no-op `.success(nil)` and nothing is sent.
    static func startDeferredCheck(
        _ deps: DeferredCheckDeps,
        generation: Int,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        guard isCurrentDeferredCheck(generation) else {
            deps.log?.log("Deferred check abandoned by reconfigure before it started")
            finishDeferredCheck(generation: generation, with: .success(nil), completion: completion)
            return
        }
        guard case let .send(rawSignals) = decideCheckGate(
            store: deps.store, environment: deps.environment, log: deps.log
        ) else {
            finishDeferredCheck(generation: generation, with: .success(nil), completion: completion)
            return
        }
        let store = deps.store
        let retrying = store.hasAttemptedAttribution
        // Read before the request, not inside the response handler: the gate is
        // closed by the response itself, so reading it afterwards would report
        // every reinstall as a first install.
        let isReinstall = store.isReinstall

        // In automatic mode the clipboard is read first, off this thread, and
        // its code rides on the one request. In every other mode nothing is read.
        firstOpenTetherFields(store: store, mode: tetherReadMode) { tether in
            sendDeferredCheck(
                deps, rawSignals: rawSignals, tether: tether, retrying: retrying,
                isReinstall: isReinstall, generation: generation, completion: completion
            )
        }
    }

    private static func sendDeferredCheck(
        _ deps: DeferredCheckDeps,
        rawSignals: Bool,
        tether: TetherRequestFields,
        retrying: Bool,
        isReinstall: Bool,
        generation: Int,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        let store = deps.store
        // Without raw signals only the device id and a Tether code can match.
        // With neither, a request cannot find anything.
        if !rawSignals, deps.collector.idfv == nil, tether.claim == nil {
            deps.log?.log("Old install with no device id or code to send, skipping the check")
            finishDeferredCheck(generation: generation, with: .success(nil), completion: completion)
            return
        }
        // Counted as failed from here: see `CountedCheck`.
        guard let counted = beginCountedCheck(store: store, generation: generation) else {
            deps.log?.log("Deferred check abandoned by reconfigure before it sent")
            finishDeferredCheck(generation: generation, with: .success(nil), completion: completion)
            return
        }
        store.hasAttemptedAttribution = true
        logCheckStart(retrying: retrying, isReinstall: isReinstall, log: deps.log)
        deps.log?.log(
            "Deferred check request: attempt \(counted.attemptNumber), raw signals \(rawSignals ? "yes" : "no")"
        )
        let request = DeferredCheckRequest(
            signals: rawSignals ? deps.collector.collect() : nil,
            deviceId: deps.collector.idfv, isReinstall: isReinstall,
            attemptNumber: counted.attemptNumber, tether: tether
        )
        performAttributionMatch(
            request: request, client: deps.client, store: store,
            log: deps.log, generation: generation
        ) { result in
            finishDeferredCheck(generation: generation, with: result, completion: completion)
        }
    }

    /// Releases the in-flight claim, answers the caller, then everyone parked on it.
    private static func finishDeferredCheck(
        generation: Int,
        with result: Result<WarpLinkDeepLink?, WarpLinkError>,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        let current = isCurrentDeferredCheck(generation)
        let parked = endDeferredCheck(generation: generation)
        if current { logCheckOutcome() }
        completion(result)
        parked.forEach { pending in SDKEnvironment.deliver { pending(result) } }
    }

    /// Answer from the cache when attribution has already completed for this
    /// install, and report whether it did. Scoped to the install, so a reinstall
    /// falls through to a real check instead of replaying the old result.
    static func answeredFromCache(
        store: Storage,
        log: Logger?,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) -> Bool {
        guard store.isAttributionComplete else { return false }
        let cached = store.cachedAttribution
        log?.log("Attribution already complete for this install, returning cached result")
        logCheckOutcome()
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
}
