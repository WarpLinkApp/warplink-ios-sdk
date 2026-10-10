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
            rateLimitSpent: false,
            isCurrent: isCurrent,
            attempt: attempt,
            completion: completion
        )
    }

    private static func perform<T>(
        number: Int,
        startedAt: TimeInterval,
        rateLimitSpent: Bool,
        isCurrent: @escaping () -> Bool,
        attempt: @escaping (Int, @escaping (Result<T, WarpLinkError>) -> Void) -> Void,
        completion: @escaping (Result<T, WarpLinkError>) -> Void
    ) {
        attempt(number) { result in
            guard let wait = nextWait(
                after: result, number: number, startedAt: startedAt,
                rateLimitSpent: rateLimitSpent, isCurrent: isCurrent
            ) else {
                completion(result)
                return
            }
            SDKEnvironment.schedule(wait) {
                guard isCurrent() else {
                    completion(result)
                    return
                }
                let spent = rateLimitSpent || result.isRateLimited
                perform(
                    number: number + 1, startedAt: startedAt, rateLimitSpent: spent,
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
        rateLimitSpent: Bool,
        isCurrent: () -> Bool
    ) -> TimeInterval? {
        guard case let .failure(error) = result else { return nil }
        guard isCurrent() else { return nil }
        // A 429 gets one retry per request, at any attempt, after the wait the
        // server asked for. It is not `isRetryable`: the other 4xx refusals
        // repeat, a rate limit lifts.
        let isRateLimited = RateLimit.isRateLimited(error)
        guard isRateLimited || RetryPolicy.isRetryable(error) else { return nil }
        // The elapsed cap, not just the attempt count. A per-attempt timeout
        // bounds the gap between bytes rather than the response, so three
        // attempts that each crawl outlast any budget stated in attempts alone.
        let elapsed = WarpLink.monotonicNow() - startedAt
        guard elapsed < RetryPolicy.totalBudget else { return nil }
        if isRateLimited {
            guard !rateLimitSpent, number < RetryPolicy.maxAttempts,
                  let wait = RateLimit.wait(for: error),
                  elapsed + wait < RetryPolicy.totalBudget else { return nil }
            return wait
        }
        return RetryPolicy.delay(beforeAttempt: number + 1)
    }
}

private extension Result {
    var isRateLimited: Bool {
        if case let .failure(error as WarpLinkError) = self { return RateLimit.isRateLimited(error) }
        return false
    }
}
