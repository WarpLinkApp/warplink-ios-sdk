import Foundation

/// Asking the server to attribute this install. The deferred check in
/// `WarpLink+DeferredDeepLink.swift` claims the check and parks callers;
/// `WarpLink+AttributionApply.swift` decides what the answer means.
extension WarpLink {

    /// Ask the server to attribute this install, up to `RetryPolicy.maxAttempts`
    /// times, and hand the answer to `completion`.
    static func performAttributionMatch(
        request: DeferredCheckRequest,
        client: APIClient,
        store: Storage,
        log: Logger?,
        generation: Int,
        pendingRetried: Bool = false,
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
                attemptAttributionMatch(
                    number: number, request: request, client: client, store: store,
                    tapId: tapId, generation: generation, done: done
                )
            },
            completion: { result in
                // A pending code is not final: wait and send the same request once.
                if !pendingRetried, let wait = pendingWait(result) {
                    retryPendingMatch(
                        after: wait, first: result, request: request, client: client,
                        store: store, log: log, generation: generation, completion: completion
                    )
                    return
                }
                // A test code or a refused one is not this install's answer.
                if let again = settleTether(result, sent: request.tether) {
                    performAttributionMatch(
                        request: request.with(tether: again), client: client, store: store,
                        log: log, generation: generation, completion: completion
                    )
                    return
                }
                applyAttributionResult(
                    result, store: store, log: log,
                    generation: generation, completion: completion
                )
            }
        )
    }
}
