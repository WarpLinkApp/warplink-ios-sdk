import Foundation

extension WarpLink {

    private static let maxInstallerIdLength = 128

    /// Claims the referral behind this install for the person who just signed up.
    ///
    /// `installerId` is your own stable id for that person. Calling again with
    /// the same id is safe: the server answers the same claim again rather
    /// than crediting twice.
    ///
    /// `.none` is an ordinary answer, not an error: there was no referral to
    /// credit. The call fails only when it cannot reach the server or the key
    /// is refused. An empty `installerId`, or one over 128 characters, fails
    /// without a request.
    public static func claimReferral(
        installerId: String,
        completion: @escaping (Result<ReferralClaimResult, WarpLinkError>) -> Void
    ) {
        guard let context = referralContext() else {
            completion(.failure(.notConfigured))
            return
        }
        guard (1...maxInstallerIdLength).contains(installerId.count) else {
            completion(.failure(.serverError(
                statusCode: 400,
                message: "installerId must be 1 to \(maxInstallerIdLength) characters"
            )))
            return
        }
        let store = ReferralServices.evidenceStore
        let evidence = ReferralClaimEvidence.current(from: store, now: ReferralServices.now())
        ReferralBoundedCall.run(
            client: context.client,
            send: { timeout, answer in
                context.client.claimReferral(
                    installerId: installerId, evidence: evidence, timeout: timeout,
                    onTokenRefused: {
                        guard let token = evidence.recoveryToken else { return }
                        store.clearToken(ifHolding: token)
                    },
                    completion: answer
                )
            },
            completion: completion
        )
    }
}
