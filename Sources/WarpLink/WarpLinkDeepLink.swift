import Foundation

/// Resolved deep link data returned by the WarpLink SDK.
public struct WarpLinkDeepLink {
    /// The unique identifier of the link.
    public let linkId: String

    /// The resolved destination URL.
    public let destination: String

    /// The iOS-specific deep link URL (e.g., `myapp://path`), if configured.
    public let deepLinkUrl: String?

    // TODO: [String: Any] is not Codable. The implementation task will need
    // a custom decoder or JSON type wrapper for serialization/deserialization.
    /// Custom parameters attached to the link.
    public let customParams: [String: Any]

    /// Whether this deep link was resolved via deferred attribution.
    public let isDeferred: Bool

    /// The type of attribution match (deterministic or probabilistic).
    public let matchType: MatchType?

    /// The confidence score of the attribution match (0.0–1.0).
    public let matchConfidence: Double?

    public init(
        linkId: String,
        destination: String,
        deepLinkUrl: String? = nil,
        customParams: [String: Any] = [:],
        isDeferred: Bool = false,
        matchType: MatchType? = nil,
        matchConfidence: Double? = nil
    ) {
        self.linkId = linkId
        self.destination = destination
        self.deepLinkUrl = deepLinkUrl
        self.customParams = customParams
        self.isDeferred = isDeferred
        self.matchType = matchType
        self.matchConfidence = matchConfidence
    }
}
