import Foundation

/// Runs one request up to `RetryPolicy.maxAttempts` times, waiting between
/// attempts, and stops early when the work has been superseded or the budget
/// has been spent.
///
/// Generic over the response so the resolve and the deferred check share one
/// implementation rather than two that drift. Kept out of `APIClient` on
/// purpose: `APIClientResolveLinkTests` drives a real `URLSession` through a
/// `URLProtocol` mock, so a retry inside `APIClient.resolveLink` would turn
/// every failure test there into three real round trips with real backoff.
enum BoundedRetry {

    /// - Parameters:
    ///   - isCurrent: false once this work has been superseded. A superseded run
    ///     stops attempting but STILL answers its own caller: swallowing the
    ///     completion here would strand a manual `handleDeepLink` caller.
    ///     Staying silent to the host is the caller's decision, made where the
    ///     host's sink is.
    ///   - attempt: performs one try. Receives the 1-based attempt number, so a
    ///     caller can shorten the timeout on the retries alone.
    ///   - completion: called exactly once, with the last result seen.
    static func run<T>(
        isCurrent: @escaping () -> Bool,
        attempt: @escaping (Int, @escaping (Result<T, WarpLinkError>) -> Void) -> Void,
        completion: @escaping (Result<T, WarpLinkError>) -> Void
    ) {
        perform(
            number: 1,
            startedAt: WarpLink.monotonicNow(),
            isCurrent: isCurrent,
            attempt: attempt,
            completion: completion
        )
    }

    private static func perform<T>(
        number: Int,
        startedAt: TimeInterval,
        isCurrent: @escaping () -> Bool,
        attempt: @escaping (Int, @escaping (Result<T, WarpLinkError>) -> Void) -> Void,
        completion: @escaping (Result<T, WarpLinkError>) -> Void
    ) {
        attempt(number) { result in
            guard let wait = nextWait(
                after: result, number: number, startedAt: startedAt, isCurrent: isCurrent
            ) else {
                completion(result)
                return
            }
            SDKEnvironment.schedule(wait) {
                guard isCurrent() else {
                    completion(result)
                    return
                }
                perform(
                    number: number + 1, startedAt: startedAt,
                    isCurrent: isCurrent, attempt: attempt, completion: completion
                )
            }
        }
    }

    /// How long to wait before the next attempt, or nil when there must not be
    /// one. Every reason to stop lives here, in the order it is cheapest to ask.
    private static func nextWait<T>(
        after result: Result<T, WarpLinkError>,
        number: Int,
        startedAt: TimeInterval,
        isCurrent: () -> Bool
    ) -> TimeInterval? {
        guard case let .failure(error) = result else { return nil }
        guard isCurrent() else { return nil }
        guard RetryPolicy.isRetryable(error) else { return nil }
        // The elapsed cap, not just the attempt count. A per-attempt timeout
        // bounds the gap between bytes rather than the response, so three
        // attempts that each crawl outlast any budget stated in attempts alone.
        guard WarpLink.monotonicNow() - startedAt < RetryPolicy.totalBudget else { return nil }
        return RetryPolicy.delay(beforeAttempt: number + 1)
    }
}
