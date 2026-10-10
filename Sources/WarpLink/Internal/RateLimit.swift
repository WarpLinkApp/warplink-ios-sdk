import Foundation

/// How a 429 travels through the SDK and how long it asks the caller to wait.
///
/// A 429 stays `.serverError(statusCode: 429, ...)`. A new `WarpLinkError` case
/// would break every host `switch` that has no `default`, so the server's
/// `Retry-After` rides in the message instead, written and read only here.
enum RateLimit {

    static let statusCode = 429

    /// The wait when the response carries no usable `Retry-After`.
    static let defaultWait: TimeInterval = 1.0

    /// A longer `Retry-After` than this is not worth holding a tap for: the
    /// error goes to the caller instead of a retry.
    static let maxWait: TimeInterval = 5.0

    private static let messagePrefix = "Rate limited"
    private static let waitMarker = "retry after "

    /// The error for a 429 response, carrying its `Retry-After` seconds.
    static func error(for response: HTTPURLResponse) -> WarpLinkError {
        let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(parseSeconds)
        let message = seconds.map { "\(messagePrefix), \(waitMarker)\($0)s" } ?? messagePrefix
        return .serverError(statusCode: statusCode, message: message)
    }

    static func isRateLimited(_ error: WarpLinkError) -> Bool {
        if case let .serverError(code, _) = error { return code == statusCode }
        return false
    }

    /// The seconds to wait before the one retry, or nil when `error` is not a
    /// 429 or asks for more than `maxWait`.
    static func wait(for error: WarpLinkError) -> TimeInterval? {
        guard case let .serverError(code, message) = error, code == statusCode else { return nil }
        let requested = requestedSeconds(in: message) ?? defaultWait
        return requested <= maxWait ? requested : nil
    }

    /// Delta-seconds only. An HTTP-date form is treated as absent, which falls
    /// back to `defaultWait`.
    private static func parseSeconds(_ header: String) -> TimeInterval? {
        guard let value = TimeInterval(header.trimmingCharacters(in: .whitespaces)),
              value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func requestedSeconds(in message: String) -> TimeInterval? {
        guard let range = message.range(of: waitMarker) else { return nil }
        return TimeInterval(message[range.upperBound...].dropLast())
    }
}
