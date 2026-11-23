import Foundation

/// The failed checks of one install: when the first and the latest happened and
/// how many there were. It decides whether the next check may ask the server:
/// the wait after a failure grows with each one, and the SDK stops asking once
/// the give-up time has passed.
struct CheckBackoff: Equatable {

    let firstFailureAt: Date
    let lastFailureAt: Date
    let failures: Int

    enum Verdict: Equatable {
        case allowed
        case waiting(until: Date)
        /// The give-up time has passed: no further check for this install.
        case gaveUp
    }

    static func firstFailure(at time: Date) -> CheckBackoff {
        CheckBackoff(firstFailureAt: time, lastFailureAt: time, failures: 1)
    }

    func recording(failureAt time: Date) -> CheckBackoff {
        CheckBackoff(firstFailureAt: firstFailureAt, lastFailureAt: time, failures: failures + 1)
    }

    func verdict(at now: Date, policy: SDKPolicy) -> Verdict {
        if now.timeIntervalSince(firstFailureAt) >= policy.giveUpAfter { return .gaveUp }
        // A clock set back leaves the last failure in the future. Waiting for a
        // time that far ahead could block the check for good, so it is allowed.
        guard lastFailureAt <= now else { return .allowed }
        let readyAt = lastFailureAt.addingTimeInterval(policy.retryDelay(afterFailures: failures))
        return now >= readyAt ? .allowed : .waiting(until: readyAt)
    }

    // MARK: - Stored form

    /// `first,last,failures`, with both times in whole seconds since 1970.
    var encoded: String {
        "\(Int(firstFailureAt.timeIntervalSince1970)),\(Int(lastFailureAt.timeIntervalSince1970)),\(failures)"
    }

    init(firstFailureAt: Date, lastFailureAt: Date, failures: Int) {
        self.firstFailureAt = firstFailureAt
        self.lastFailureAt = lastFailureAt
        self.failures = failures
    }

    /// Nil for text that is not a stored backoff, which reads as no failures.
    init?(encoded: String) {
        let parts = encoded.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let first = TimeInterval(parts[0]),
              let last = TimeInterval(parts[1]),
              let failures = Int(parts[2]), failures >= 1 else { return nil }
        self.init(
            firstFailureAt: Date(timeIntervalSince1970: first),
            lastFailureAt: Date(timeIntervalSince1970: last),
            failures: failures
        )
    }
}
