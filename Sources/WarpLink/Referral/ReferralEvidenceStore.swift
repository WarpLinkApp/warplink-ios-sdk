import Foundation

/// What the SDK remembers from a match so a later claim can name it.
///
/// A claim happens after sign-up, often in a later session, when the match
/// response is long gone. The claim route accepts the install the match
/// created and the recovery token behind it, so both are kept here. Neither
/// is shown to the host.
struct ReferralEvidence: Codable, Equatable {
    var installId: String?
    var recoveryToken: String?
    var recoveryTokenExpiresAt: Date?

    /// The token, or nil when none is held or it has run out.
    func usableToken(at now: Date) -> String? {
        guard let token = recoveryToken else { return nil }
        if let expiry = recoveryTokenExpiresAt, expiry <= now { return nil }
        return token
    }
}

final class ReferralEvidenceStore {

    private static let key = "warplink_referral_evidence"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var evidence: ReferralEvidence {
        guard let data = defaults.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode(ReferralEvidence.self, from: data)
        else { return ReferralEvidence() }
        return stored
    }

    /// Remembers the install a match created. A response without one leaves the
    /// earlier value alone.
    func remember(installId: String?) {
        guard let installId = installId else { return }
        update { $0.installId = installId }
    }

    /// Remembers the token a claim should carry. An open of a referral link
    /// hands one out too, and a newer token replaces the older one.
    func remember(token: String, expiresAt: Date?) {
        update {
            $0.recoveryToken = token
            $0.recoveryTokenExpiresAt = expiresAt
        }
    }

    /// Drops the held token once the server has refused it, so no later claim
    /// sends it again. Kept only while it is still `token`: a newer one may have
    /// replaced it during the request. The install id stays, since the claim can
    /// still name the install without a token.
    func clearToken(ifHolding token: String) {
        update {
            guard $0.recoveryToken == token else { return }
            $0.recoveryToken = nil
            $0.recoveryTokenExpiresAt = nil
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Self.key)
    }

    /// One read-change-write under the lock, so two writers cannot overwrite
    /// each other and a check made inside `change` still holds when it writes.
    private func update(_ change: (inout ReferralEvidence) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var current = evidence
        change(&current)
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
