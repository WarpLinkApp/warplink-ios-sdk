import Foundation

/// Attempting the attribution match, and applying its answer.
///
/// Split out of `WarpLink+DeferredDeepLink.swift`, which orchestrates the check
/// (claiming it, parking callers, answering from the cache) and was already past
/// the file size cap. Asking the server, and deciding what its answer means, is
/// a separate job, and it is the one the bounded retry wraps.
extension WarpLink {

    /// Ask the server to attribute this install, up to `RetryPolicy.maxAttempts`
    /// times, and hand the answer to `completion`.
    static func performAttributionMatch(
        signals: DeviceSignals,
        client: APIClient,
        store: Storage,
        log: Logger?,
        deviceId: String?,
        isReinstall: Bool,
        generation: Int,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        // One id for this check, repeated on every attempt. LOG-ONLY here:
        // `app_installs.click_id` is uniquely indexed, but the server derives
        // its value from the KV deferred payload rather than from the client,
        // so this header dedupes nothing. Sent so one check is traceable.
        let tapId = UUID().uuidString

        BoundedRetry.run(
            isCurrent: { isCurrentDeferredCheck(generation) },
            attempt: { number, done in
                let timeout = RetryPolicy.timeout(forAttempt: number)
                // Every attempt is bounded, the first included, and bounded in
                // wall time rather than only between bytes. Same watchdog as
                // the resolve path, for the reasons stated there, and the same
                // fresh connection after a timeout or an OS-cancelled attempt.
                let task = AttemptWatchdog.bound(
                    timeout: timeout,
                    completion: done,
                    discardConnection: { client.transport.discardConnections() }
                ) { answer in
                    client.matchAttribution(
                        signals: signals, sdkVersion: sdkVersion,
                        deviceId: deviceId, isReinstall: isReinstall,
                        tapId: tapId, timeout: timeout, completion: answer
                    )
                }
                // Recorded so a reconfigure can stop this attempt rather than
                // merely ignore its answer.
                setInFlightDeferredCheck(task, generation: generation)
            },
            completion: { result in
                applyAttributionResult(
                    result, store: store, log: log,
                    generation: generation, completion: completion
                )
            }
        )
    }

    // MARK: - Private

    /// What the whole run, retries included, amounted to.
    private static func applyAttributionResult(
        _ result: Result<AttributionResponse, WarpLinkError>,
        store: Storage,
        log: Logger?,
        generation: Int,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        switch result {
        case let .failure(error):
            deliverAttributionFailure(error, log: log, generation: generation, completion: completion)
        case let .success(response):
            handleAttributionResponse(
                response, store: store, log: log,
                generation: generation, completion: completion
            )
        }
    }

    /// The run failed, every attempt spent. THE GATE STAYS OPEN.
    ///
    /// Nothing here calls `markAttributionComplete`, and nothing may: three
    /// failed attempts are still "did not complete", so the next launch tries
    /// again. Closing the gate on a retry-exhausted failure would cost a user
    /// who happened to be offline at launch their attribution for good, which
    /// is worse than the defect the retry fixes.
    private static func deliverAttributionFailure(
        _ error: WarpLinkError,
        log: Logger?,
        generation: Int,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        // An abandoned check answers with the no-op success, exactly as its
        // response path does. A reconfigure CANCELS the request it abandons, and
        // that surfaces as `.networkError(URLError(.cancelled))`; routing it on
        // would push an error into `onLink` for a reconfigure the app asked for.
        guard isCurrentDeferredCheck(generation) else {
            log?.log("Deferred check abandoned by reconfigure, discarding its failure")
            completion(.success(nil))
            return
        }
        log?.log("Attribution match failed (will retry next launch): \(error.localizedDescription)")
        completion(.failure(error))
    }

    private static func handleAttributionResponse(
        _ response: AttributionResponse,
        store: Storage,
        log: Logger?,
        generation: Int,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        let matched = deferredLink(from: response)
        let definitive = isDefinitive(response, routed: matched)

        // A check abandoned by a reconfigure answers with the `.success(nil)`
        // no-op, never a fabricated `.notConfigured`: the SDK is configured, and
        // the auto path routes this completion straight to the host's `onLink`,
        // where an invented error would be a misleading thing to show a user.
        // `dispatchToOnLink` already swallows `.success(nil)`, so an abandoned
        // auto check is silent (parity with Android).
        guard applyIfCurrent(
            matched, definitive: definitive, store: store, generation: generation
        ) else {
            log?.log("Deferred check abandoned by reconfigure, discarding its result")
            completion(.success(nil))
            return
        }

        // After the generation test: a superseded check must not replace the
        // install id the winning answer left.
        ReferralServices.evidenceStore.remember(installId: response.installId)
        log?.log(resultLog(matched: matched, definitive: definitive))
        completion(.success(matched))
    }

    /// Whether this response settles attribution for the install.
    ///
    /// A confirmed no-match does: the server looked, found nothing, and the
    /// check has done its job. A `matched` response the SDK cannot route does
    /// NOT, whatever the server called it. It names no link and carries no
    /// destination, so `deferredLink(from:)` throws it away and the host is told
    /// nothing matched. Closing the gate on that spends the install's one check
    /// on an answer nobody can act on, and nothing ever retries: the gate
    /// outlives every relaunch, and only a reinstall clears it.
    private static func isDefinitive(
        _ response: AttributionResponse, routed: WarpLinkDeepLink?
    ) -> Bool {
        !response.matched || routed != nil
    }

    private static func resultLog(
        matched: WarpLinkDeepLink?, definitive: Bool
    ) -> String {
        if let matched = matched {
            return "Deferred deep link matched: \(matched.linkId)"
        }
        return definitive
            ? "No deferred deep link match"
            : "Attribution matched with nothing to route to, retrying next launch"
    }

    /// Persist a definitive response, but only while `generation` is still the
    /// live check; returns false for an abandoned one, which applies nothing.
    ///
    /// A response that is not `definitive` also writes nothing, and returns
    /// true: this IS the live check, it simply has nothing worth keeping and
    /// must leave the gate open for the next launch.
    ///
    /// The generation test and the writes share a single lock hold: a
    /// `configure()` landing between them would let a stale no-match mark
    /// attribution complete and blank the match the successor cached, since both
    /// `Storage` instances persist to the same defaults.
    private static func applyIfCurrent(
        _ deepLink: WarpLinkDeepLink?,
        definitive: Bool,
        store: Storage,
        generation: Int
    ) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard generation == deferredCheckGeneration else { return false }
        guard definitive else { return true }
        // A definitive server response (match or no-match) consumes first launch.
        store.markAttributionComplete()
        store.cachedAttribution = deepLink
        return true
    }

    private static func deferredLink(from response: AttributionResponse) -> WarpLinkDeepLink? {
        ReferralMatch.deepLink(from: response)
    }
}
