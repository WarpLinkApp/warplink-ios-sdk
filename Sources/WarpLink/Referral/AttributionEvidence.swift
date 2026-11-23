import Foundation

/// How a match was made, as the server reports it. Stays with the result of the
/// match for good, including when the same match is later replayed.
public enum MatchMethod: String, Codable, Sendable {
    /// A single-use recovery token the user pasted, or the app read, at install.
    case installToken = "install_token"
    case androidReferrer = "android_referrer"
    case deviceId = "device_id"
    /// The app was opened from the link on a device that already had it.
    case linkOpen = "link_open"
    case probabilistic

    /// Reads a method name. The server calls the install referrer match
    /// `referrer`, and rows from before that name carry `android_referrer`.
    /// Both give `.androidReferrer`. Any other unknown name gives `nil`.
    public init?(rawValue: String) {
        switch rawValue {
        case "install_token": self = .installToken
        case "referrer", "android_referrer": self = .androidReferrer
        case "device_id": self = .deviceId
        case "link_open": self = .linkOpen
        case "probabilistic": self = .probabilistic
        default: return nil
        }
    }
}

/// How strong the evidence behind a match is.
public enum EvidenceClass: String, Codable, Sendable {
    case exact
    case estimated
    /// Matched through the link id alone, with no token behind it.
    case legacyLink = "legacy_link"
}

/// Whether this answer is the first one for the match or a repeat of it.
public enum ReplayState: String, Codable, Sendable {
    case original
    case replayed
}
