import Foundation

/// The stores the referral handoff uses, in one place so a test can replace
/// them. Restored by `WarpLink.reset()`, like `SDKEnvironment`.
enum ReferralServices {

    static var pendingStore: ReferralPendingStore = KeychainPendingStore()
    static var evidenceStore = ReferralEvidenceStore()
    static var now: () -> Date = Date.init

    /// The environment the stores above belong to.
    private(set) static var environment = KeyEnvironment.production

    /// Bumped whenever a redeem run in flight must not apply its answer: the key
    /// changed, or the attribution it would feed was cleared. Written under
    /// `WarpLink.lock`, which a redeem holds while it checks and applies.
    private(set) static var epoch = 0

    /// Points the stores at `environment`'s namespace and orphans any redeem run
    /// in flight, because every call is a key change. The same environment keeps
    /// the stores it has, so a test double stays in place.
    static func use(_ environment: KeyEnvironment) {
        lock.lock(); defer { lock.unlock() }
        epoch += 1
        guard environment != self.environment else { return }
        self.environment = environment
        pendingStore = KeychainPendingStore(environment: environment)
        evidenceStore = ReferralEvidenceStore(environment: environment)
    }

    /// Forgets the held invitation and evidence, and orphans a redeem run in
    /// flight so its answer cannot refill what was just cleared.
    static func clearAll() {
        lock.lock(); defer { lock.unlock() }
        pendingStore.clear()
        evidenceStore.clear()
        epoch += 1
    }

    /// True while a redeem run is on the wire. A paste and a launch resume that
    /// meet are collapsed into one request, so one token is delivered once.
    private(set) static var redeemInFlight = false
    private static let lock = NSLock()

    /// Claims the right to send a redeem request. False when one is running.
    static func beginRedeem() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if redeemInFlight { return false }
        redeemInFlight = true
        return true
    }

    static func endRedeem() {
        lock.lock(); defer { lock.unlock() }
        redeemInFlight = false
    }

    /// Keeps the token an in-app open of a referral link handed out, so a later
    /// claim can carry it. A value that is not a well-formed token is dropped.
    static func remember(openToken: String?) {
        guard let invitation = openToken.flatMap(ReferralInvitation.parse) else { return }
        evidenceStore.remember(token: invitation.token, expiresAt: invitation.expiresAt)
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        environment = .production
        pendingStore = KeychainPendingStore()
        evidenceStore = ReferralEvidenceStore()
        now = Date.init
        epoch += 1
        redeemInFlight = false
    }
}
