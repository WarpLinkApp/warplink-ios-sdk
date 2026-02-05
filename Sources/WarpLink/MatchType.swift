import Foundation

/// The type of attribution match used to resolve a deferred deep link.
public enum MatchType: String, Codable, Sendable {
    case deterministic
    case probabilistic
}
