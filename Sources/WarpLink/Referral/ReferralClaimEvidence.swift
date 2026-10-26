import Foundation

/// What a claim sends to name the referral: the install the match created and
/// the recovery token behind it. Both are optional on the wire.
struct ReferralClaimEvidence: Equatable {
    let installId: String?
    let recoveryToken: String?

    /// Reads what the SDK holds. A token that has run out is left out, since
    /// the server would refuse it; an install id that is not a UUID is left
    /// out for the same reason.
    static func current(
        from store: ReferralEvidenceStore, now: Date
    ) -> ReferralClaimEvidence {
        let held = store.evidence
        let installId = held.installId.flatMap { UUID(uuidString: $0) == nil ? nil : $0 }
        return ReferralClaimEvidence(
            installId: installId, recoveryToken: held.usableToken(at: now)
        )
    }

    func body(installerId: String, bundleIdentifier: String?) -> [String: Any] {
        var body: [String: Any] = ["installer_id": installerId, "platform": "ios"]
        if let bundleIdentifier = bundleIdentifier, !bundleIdentifier.isEmpty {
            body["app_bundle_id"] = bundleIdentifier
        }
        if let installId = installId { body["install_id"] = installId }
        if let recoveryToken = recoveryToken { body["recovery_token"] = recoveryToken }
        return body
    }
}
