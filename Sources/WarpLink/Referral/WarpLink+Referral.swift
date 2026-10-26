import Foundation

extension WarpLink {

    /// Redeems an invitation the user pasted.
    ///
    /// Call this only from a user action, with the text the system paste
    /// control hands you (`WarpLinkPasteButton`, `WarpLinkUIPasteButton`). The
    /// SDK never reads the pasteboard on its own.
    ///
    /// - `.success(link)`: the invitation matched and `link` is the result. It
    ///   is also cached as `attributionResult`.
    /// - `.success(nil)`: the text was not a WarpLink invitation, or the
    ///   invitation matched nothing. Nothing is confirmed, so do not tell the
    ///   user a referral was applied.
    /// - `.failure`: the invitation is invalid or expired (the message says how
    ///   to open the link again), or the network failed. After a network
    ///   failure the SDK keeps the invitation on the device and tries again
    ///   on a later launch, a bounded number of times.
    ///
    /// Onboarding does not wait on this: skipping it, or any failure, leaves
    /// the app fully usable.
    public static func redeemInvitation(
        text: String,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        guard let context = referralContext() else {
            completion(.failure(.notConfigured))
            return
        }
        ReferralRedeemer.redeem(text: text, context: context, completion: completion)
    }

    /// Finishes an invitation that a network failure left undelivered, and
    /// routes a match to `onLink`. Called by `configure()`.
    ///
    /// Only a match reaches `onLink`. No screen is waiting on a launch resume,
    /// so a failure is logged by the redeemer and kept for the next launch.
    static func resumePendingInvitation() {
        guard let context = referralContext() else { return }
        ReferralRedeemer.resume(context: context) { result in
            guard case let .success(link?) = result else { return }
            dispatchToOnLink(.success(link))
        }
    }

    static func referralContext() -> ReferralRedeemer.Context? {
        lock.lock(); defer { lock.unlock() }
        guard let client = apiClient, let store = storage else { return nil }
        return ReferralRedeemer.Context(
            client: client, store: store, deviceId: fingerprintCollector?.idfv, log: logger
        )
    }
}
