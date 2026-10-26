import Foundation

/// The one invitation the user pasted that has not been delivered yet.
struct PendingRedemption: Codable, Equatable {

    /// Redeem runs started for this token, counting the one in progress.
    static let maxAttempts = 5

    let token: String
    let expiresAt: Date
    var attempts: Int

    init(token: String, expiresAt: Date, attempts: Int = 0) {
        self.token = token
        self.expiresAt = expiresAt
        self.attempts = attempts
    }

    func isExpired(at now: Date) -> Bool { expiresAt <= now }

    var hasAttemptsLeft: Bool { attempts < Self.maxAttempts }
}

/// Keeps the pasted invitation on the device so a network failure can be
/// retried on a later launch, and so a retry never delivers the match twice.
///
/// Holds at most one record: a newer paste replaces the older one.
protocol ReferralPendingStore {
    func load() -> PendingRedemption?
    @discardableResult func save(_ record: PendingRedemption) -> Bool
    func clear()
}
