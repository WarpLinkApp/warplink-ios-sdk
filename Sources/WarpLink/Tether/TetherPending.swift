import Foundation

/// The `pending` Tether answer: a genuine code whose tap record has not reached
/// the server's region yet. It is not final. The SDK waits, sends the same
/// request once more, and keeps attribution open if the answer is still pending.
enum TetherPending {

    /// The wait when the answer carries no `retry_after_seconds`.
    static let defaultWait: TimeInterval = 20

    /// The longest wait the SDK honours, whatever the server asks.
    static let maxWait: TimeInterval = 30

    /// The seconds to wait before the one retry, or nil when `tether` is not a
    /// pending answer.
    static func wait(for tether: TetherResponse?) -> TimeInterval? {
        guard let tether = tether, tether.isPending else { return nil }
        let asked = tether.retryAfterSeconds.map(TimeInterval.init) ?? defaultWait
        return min(asked, maxWait)
    }
}
