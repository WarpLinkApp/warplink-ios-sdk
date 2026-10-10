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
    /// credential: a probabilistic match is a best guess from a
    /// network-shaped fingerprint and can name the wrong user. Authenticate
    /// the user and check authorization separately before showing private
    /// data or doing anything sensitive, guaranteed match or not.
    public let matchGuaranteed: Bool

    public init(
        linkId: String,
        destination: String,
        deepLinkUrl: String? = nil,
        customParams: [String: JSONValue] = [:],
        isDeferred: Bool = false,
        matchType: MatchType? = nil,
        matchConfidence: Double? = nil,
        matchGuaranteed: Bool = false
    ) {
        self.linkId = linkId
        self.destination = destination
        self.deepLinkUrl = deepLinkUrl
        self.customParams = customParams
        self.isDeferred = isDeferred
        self.matchType = matchType
        self.matchConfidence = matchConfidence
        self.matchGuaranteed = matchGuaranteed
    }

    /// Decodes leniently for `matchGuaranteed`.
    ///
    /// This type is persisted as the cached attribution result, so an app
    /// upgrading from an SDK that predates the field has a stored payload
    /// without it. The synthesized decoder would throw `keyNotFound` on every
    /// one of those and the cached match would be lost on upgrade. Missing
    /// means `false`, which is the safe direction: a host gating a sensitive
    /// action on this can only ever become more cautious, never less.
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
    }
}
