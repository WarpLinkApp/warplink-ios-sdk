import Foundation

/// The answer to `WarpLink.claimReferral(installerId:completion:)`.
///
/// `none` is an ordinary answer, not an error: it means the claim found no
/// referral to credit, and nothing was recorded for it.
public struct ReferralClaimResult: Equatable, Sendable {

    public enum Status: String, Codable, Sendable {
        /// The referral was credited to this installer.
        case claimed
        /// Credited, but marked for review, for example a claim made after the window.
        case flagged
        /// Not credited again: the installer or the app already holds a claim.
        case ignored
        /// No referral was found for this installer.
        case none
    }

    public let status: Status

    /// The id of the referral, or nil when the status is `none`.
    public let referralId: String?

    /// The link the referral came from, or nil when the status is `none`.
    public let linkId: String?

    /// The short URL of that link, or nil when the status is `none`.
    public let linkUrl: String?

    /// How the referral was matched, or nil when the status is `none`.
    public let matchMethod: MatchMethod?

    /// True when the match rests on exact evidence rather than an estimate.
    public let isExact: Bool

    /// The confidence of an estimated match, or nil when there is none.
    public let matchConfidence: Double?

    /// Reasons the referral was flagged, for example `outside_window`.
    public let flags: [String]

    /// For `ignored`, the referral that already holds the credit.
    public let duplicateOf: String?

    /// True when this call replaced an earlier estimate with an exact match.
    public let updated: Bool

    public let replayState: ReplayState?

    static let none = ReferralClaimResult(status: .none)

    public init(
        status: Status,
        referralId: String? = nil,
        linkId: String? = nil,
        linkUrl: String? = nil,
        matchMethod: MatchMethod? = nil,
        isExact: Bool = false,
        matchConfidence: Double? = nil,
        flags: [String] = [],
        duplicateOf: String? = nil,
        updated: Bool = false,
        replayState: ReplayState? = nil
    ) {
        self.status = status
        self.referralId = referralId
        self.linkId = linkId
        self.linkUrl = linkUrl
        self.matchMethod = matchMethod
        self.isExact = isExact
        self.matchConfidence = matchConfidence
        self.flags = flags
        self.duplicateOf = duplicateOf
        self.updated = updated
        self.replayState = replayState
    }
}

extension ReferralClaimResult {

    /// Reads the claim route's 200 body. An unreadable body is `none`, since a
    /// claim must never fail the sign-up that triggered it.
    static func decode(data: Data?) -> ReferralClaimResult {
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = (json["status"] as? String).flatMap({ Status(rawValue: $0) })
        else { return .none }
        let link = json["link"] as? [String: Any]
        let match = json["match"] as? [String: Any]
        return ReferralClaimResult(
            status: status,
            referralId: json["referral_id"] as? String,
            linkId: link?["id"] as? String,
            linkUrl: link?["url"] as? String,
            matchMethod: (match?["method"] as? String).flatMap { MatchMethod(rawValue: $0) },
            isExact: match?["exact"] as? Bool ?? false,
            matchConfidence: match?["confidence"] as? Double,
            flags: json["flags"] as? [String] ?? [],
            duplicateOf: json["duplicate_of"] as? String,
            updated: json["updated"] as? Bool ?? false,
            replayState: (json["replay_state"] as? String).flatMap { ReplayState(rawValue: $0) }
        )
    }
}
