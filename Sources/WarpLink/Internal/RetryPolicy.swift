import Foundation

/// Which failures are worth another attempt, how long to wait first, and when
/// to stop.
///
/// Only transient failures qualify. Every 4xx is a refusal the server will
/// repeat, so retrying one spends the user's time on a link that was never
/// going to resolve.
enum RetryPolicy {

    /// The first attempt plus two retries, and the bound `BoundedRetry`
    /// enforces.
    static let maxAttempts = 3

    /// Base waits before attempts 2 and 3. The wait SCHEDULE, not the bound: a
    /// run with more attempts than waits repeats the last one.
    static let baseDelays: [TimeInterval] = [0.5, 1.0]

    /// Up to this much extra per wait, so a fleet coming back from one outage
    /// does not resend in lockstep.
    static let maxJitter: TimeInterval = 0.15

    /// Attempt 1's own timeout. Longer than a retry's, because a first attempt
    /// on a slow but working connection is the common case, and short enough
    /// that two more attempts still fit inside the budget.
    static let firstAttemptTimeout: TimeInterval = 4.0

    /// Attempts 2 and 3. The connection has already failed once by then, so
    /// waiting as long again buys little.
    static let retryAttemptTimeout: TimeInterval = 3.0

    /// The whole run stops once this much time has passed, checked before each
    /// retry. This is the SECOND guard, not the only one: every attempt now
    /// carries its own timeout, but `timeoutIntervalForRequest` bounds the gap
    /// between bytes rather than the response, so a server dripping bytes can
    /// outlast a per-attempt timeout. 4 + 0.5 + 3 + 1 + 3 is about twelve
    /// seconds.
    static let totalBudget: TimeInterval = 12.0

    /// The timeout for attempt `number`, 1-based.
    ///
    /// EVERY attempt is bounded, attempt 1 included. The SDK sets no timeout of
    /// its own anywhere in Sources/, so an unbounded first attempt inherits
    /// URLSession's 60 second default. On the network this retry exists for the
    /// first attempt hangs rather than failing, so leaving it unbounded would
    /// spend the whole budget before any retry ran.
    static func timeout(forAttempt number: Int) -> TimeInterval {
        number == 1 ? firstAttemptTimeout : retryAttemptTimeout
    }

    static func isRetryable(_ error: WarpLinkError) -> Bool {
        switch error {
        case let .networkError(underlying):
            return isTransientTransportError(underlying)
        case let .serverError(statusCode, _):
            // `statusCode >= 500`, not "any serverError". The resolve parser's
            // `default:` branch also produces .serverError for 410 GONE and for
            // 429, and statusCode 0 stands for "Invalid URL" and "No HTTP
            // response". None of those improve on a second attempt.
            return statusCode >= 500
        case .notConfigured, .invalidApiKeyFormat, .invalidApiKey, .invalidURL,
             .linkNotFound, .passwordRequired, .decodingError:
            return false
        }
    }

    /// The wait before attempt number `attempt`, 1-based, or nil when there
    /// must not be one.
    ///
    /// `maxAttempts` is the bound, and it is the only one. A run with more
    /// attempts than `baseDelays` has waits repeats the last wait rather than
    /// stopping, so a constant named "max attempts" cannot be quietly overruled
    /// by the length of a list of delays.
    static func delay(beforeAttempt attempt: Int) -> TimeInterval? {
        guard attempt >= 2, attempt <= maxAttempts, !baseDelays.isEmpty else { return nil }
        let index = min(attempt - 2, baseDelays.count - 1)
        return baseDelays[index] + Double.random(in: 0...maxJitter)
    }

    /// `.networkError` carries a bare `Error` and nothing in the SDK casts it,
    /// so this is the first place that asks what actually went wrong.
    private static func isTransientTransportError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .cannotConnectToHost, .cannotFindHost,
             .dnsLookupFailed, .networkConnectionLost,
             .notConnectedToInternet, .dataNotAllowed, .cancelled:
            // `.cancelled` belongs here now, not in a refused-outright branch:
            // it is what a supersede or a reconfigure causes on purpose, but it
            // is ALSO what the OS reports for a connection that died while the
            // app was suspended, and a live tap reusing that connection fails
            // the same way (warplink-i7oa). This function cannot tell the two
            // apart from the error alone, and it does not have to: `BoundedRetry`
            // already asks `isCurrent()` before it ever asks this, and a
            // supersede or a reconfigure bumps its generation BEFORE it cancels
            // anything (see `WarpLink+Supersede.swift`), so by the time a
            // superseded or abandoned attempt's `.cancelled` reaches here,
            // `isCurrent()` has already stopped it. Whatever DOES reach here is
            // still wanted, so it is worth another attempt like any other
            // transient failure.
            return true
        default:
            return false
        }
    }
}
