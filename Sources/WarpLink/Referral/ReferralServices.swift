import Foundation

/// The stores the referral handoff uses, in one place so a test can replace
/// them. Restored by `WarpLink.reset()`, like `SDKEnvironment`.
enum ReferralServices {

    static var pendingStore: ReferralPendingStore = KeychainPendingStore()
    static var evidenceStore = ReferralEvidenceStore()
    static var now: () -> Date = Date.init

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
        pendingStore = KeychainPendingStore()
        evidenceStore = ReferralEvidenceStore()
        now = Date.init
        redeemInFlight = false
    }
}
