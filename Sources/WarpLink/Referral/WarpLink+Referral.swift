import Foundation

extension WarpLink {

    /// Redeems a Tether code or invitation the user pasted.
    ///
    /// Call this only from a user action, with the text the system paste
    /// control hands you (`WarpLinkPasteButton`, `WarpLinkUIPasteButton`). This
    /// call never reads the pasteboard, and it does not clear it: the paste
    /// controls do both, because only they know the clipboard has not changed.
    /// Only text that is a WarpLink code or invitation is sent.
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
        // An invitation answers its own caller. It never replaces the link onLink
        // already holds: only a Tether read does.
        var own = context
        own.routesExactToOnLink = false
        ReferralRedeemer.redeem(
            text: text, stamp: nil, acceptingInvitation: true, context: own
        ) { result, _ in
            completion(result)
        }
    }

    /// Redeems text a paste control handed over. `stamp` is the clipboard's
    /// `changeCount` at the paste, so the code is cleared only if it is still
    /// there. `acceptingInvitation` is true only for the control that reports
    /// the older invitation result.
    static func redeemPasted(
        text: String?,
        stamp: Int?,
        acceptingInvitation: Bool = false,
        completion: @escaping ReferralRedeemer.Report
    ) {
        guard let context = referralContext() else {
            completion(.failure(.notConfigured), ReferralRedeemer.Detail())
            return
        }
        ReferralRedeemer.redeem(
            text: text, stamp: stamp, acceptingInvitation: acceptingInvitation,
            context: context, completion: completion
        )
    }

    /// Finishes an invitation that a network failure left undelivered, and
    /// routes a match to `onLink`. Called by `configure()`.
    ///
    /// Only a match reaches `onLink`. No screen is waiting on a launch resume,
    /// so a failure is logged by the redeemer and kept for the next launch.
    static func resumePendingInvitation() {
        guard let context = referralContext() else { return }
        ReferralRedeemer.resume(context: context) { result, detail in
            guard case let .success(link?) = result, !detail.routedToOnLink,
                  let generation = detail.clearGeneration else { return }
            dispatchAttributionToOnLink(.success(link), ifGeneration: generation)
        }
    }

    static func referralContext() -> ReferralRedeemer.Context? {
        lock.lock(); defer { lock.unlock() }
        guard let client = apiClient, let store = storage else { return nil }
        return ReferralRedeemer.Context(
            client: client, store: store, deviceId: fingerprintCollector?.idfv, log: logger,
            installationId: store.installationId,
            readMode: options?.tetherReadMode ?? .pasteButton
        )
    }
}
