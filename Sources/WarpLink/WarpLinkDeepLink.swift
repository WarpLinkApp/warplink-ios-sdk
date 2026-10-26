import Foundation

/// Resolved deep link data returned by the WarpLink SDK.
public struct WarpLinkDeepLink: Codable, Sendable, Equatable {
    /// The unique identifier of the link.
    public let linkId: String

    /// The resolved destination URL.
    public let destination: String

    /// The iOS-specific deep link URL (e.g., `myapp://path`), if configured.
    public let deepLinkUrl: String?

    /// Custom parameters attached to the link.
    ///
    /// Values are `JSONValue` (a `Codable`/`Sendable` JSON wrapper). Read them
    /// with the typed accessors, e.g. `customParams["id"]?.stringValue`.
    public let customParams: [String: JSONValue]

    /// Whether this deep link was resolved via deferred attribution.
    public let isDeferred: Bool

    /// The type of attribution match (deterministic or probabilistic).
    public let matchType: MatchType?

    /// The confidence score of the attribution match (0.0–1.0).
    public let matchConfidence: Double?

    /// True only when the match was deterministic. Use it, like
    /// `matchConfidence`, to pick the destination to route to, not as a
    /// credential. A probabilistic match is an estimate from device signals,
    /// namely the IP address and language, with time zone when available. Use it
    /// to route the user, not to identify them. Authenticate the user and
    /// check authorization separately before showing private data or doing
    /// anything sensitive, guaranteed match or not.
    public let matchGuaranteed: Bool

    /// The stable id of the attribution this link came from. It is the same on
    /// every replay of the match. Nil for a link that did not come from an
    /// attribution, and for a payload cached before SDK 1.2.0.
    public let attributionId: String?

    /// How the match was made. Nil when the source is not known.
    public let matchMethod: MatchMethod?

    /// How strong the evidence is. Nil when the source is not known, which is
    /// the safe reading: a host never treats an unknown match as exact.
    public let evidenceClass: EvidenceClass?

    /// Whether this is the first answer for the match or a repeat of it.
    public let replayState: ReplayState?

    /// The link parameters the server captured at the tap. Empty when none.
    public let capturedParams: [String: JSONValue]

    /// When the link was tapped, as the ISO 8601 string the server sent. Nil
    /// when the server did not record a tap.
    public let tappedAt: String?

    public init(
        linkId: String,
        destination: String,
        deepLinkUrl: String? = nil,
        customParams: [String: JSONValue] = [:],
        isDeferred: Bool = false,
        matchType: MatchType? = nil,
        matchConfidence: Double? = nil,
        matchGuaranteed: Bool = false,
        attributionId: String? = nil,
        matchMethod: MatchMethod? = nil,
        evidenceClass: EvidenceClass? = nil,
        replayState: ReplayState? = nil,
        capturedParams: [String: JSONValue] = [:],
        tappedAt: String? = nil
    ) {
        self.linkId = linkId
        self.destination = destination
        self.deepLinkUrl = deepLinkUrl
        self.customParams = customParams
        self.isDeferred = isDeferred
        self.matchType = matchType
        self.matchConfidence = matchConfidence
        self.matchGuaranteed = matchGuaranteed
        self.attributionId = attributionId
        self.matchMethod = matchMethod
        self.evidenceClass = evidenceClass
        self.replayState = replayState
        self.capturedParams = capturedParams
        self.tappedAt = tappedAt
    }

    /// Decodes leniently for every field added after 1.0.
    ///
    /// This type is persisted as the cached attribution result, so an app
    /// upgrading from an SDK that predates a field has a stored payload without
    /// it. The synthesized decoder would throw `keyNotFound` on every one of
    /// those and the cached match would be lost on upgrade. Missing
    /// `matchGuaranteed` means `false`, which is the safe direction: a host
    /// gating a sensitive action on this can only ever become more cautious,
    /// never less. The 1.2.0 evidence fields decode to nil (or empty), and a
    /// value this SDK does not know also decodes to nil instead of failing the
    /// whole payload.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        linkId = try container.decode(String.self, forKey: .linkId)
        destination = try container.decode(String.self, forKey: .destination)
        deepLinkUrl = try container.decodeIfPresent(String.self, forKey: .deepLinkUrl)
        customParams =
            try container.decodeIfPresent([String: JSONValue].self, forKey: .customParams) ?? [:]
        isDeferred = try container.decodeIfPresent(Bool.self, forKey: .isDeferred) ?? false
        matchType = try container.decodeIfPresent(MatchType.self, forKey: .matchType)
        matchConfidence = try container.decodeIfPresent(Double.self, forKey: .matchConfidence)
        matchGuaranteed =
            try container.decodeIfPresent(Bool.self, forKey: .matchGuaranteed) ?? false
        attributionId = try container.decodeIfPresent(String.self, forKey: .attributionId)
        matchMethod = try? container.decodeIfPresent(MatchMethod.self, forKey: .matchMethod)
        evidenceClass = try? container.decodeIfPresent(EvidenceClass.self, forKey: .evidenceClass)
        replayState = try? container.decodeIfPresent(ReplayState.self, forKey: .replayState)
        capturedParams =
            try container.decodeIfPresent([String: JSONValue].self, forKey: .capturedParams) ?? [:]
        tappedAt = try container.decodeIfPresent(String.self, forKey: .tappedAt)
    }
}
