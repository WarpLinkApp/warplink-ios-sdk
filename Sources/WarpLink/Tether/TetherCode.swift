import Foundation

/// A code the SDK recognises on the clipboard, and the only text it sends.
///
/// Anything else stays on the device: it is not sent, stored or logged.
enum TetherCode: Equatable {

    /// `wl1_` followed by a recovery token.
    case live(String)

    /// `wl1t_` followed by a signed body. A test code records nothing.
    case test(String)

    /// An unprefixed invitation token, copied by pages that predate Tether.
    case invitation(String)

    static let livePrefix = "wl1_"
    static let testPrefix = "wl1t_"

    /// The longest code the match route accepts.
    static let maxLength = 200

    private static let liveLifetime: TimeInterval = 24 * 60 * 60
    private static let testLifetime: TimeInterval = 15 * 60

    /// The code in `text`, or nil when `text` is not one. The test prefix is
    /// checked first, and `text` is trimmed. An unprefixed invitation parses
    /// only when `acceptingInvitation` is true: the explicit invitation paths
    /// ask for it, and no read of the clipboard by the SDK does.
    static func parse(_ text: String, acceptingInvitation: Bool = false) -> TetherCode? {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.count <= maxLength else { return nil }
        if hasBody(candidate, after: testPrefix) { return .test(candidate) }
        if hasBody(candidate, after: livePrefix) { return .live(candidate) }
        guard acceptingInvitation else { return nil }
        return ReferralInvitation.parse(candidate).map { .invitation($0.token) }
    }

    /// The text as it is sent, trimmed.
    var wireText: String {
        switch self {
        case let .live(text), let .test(text), let .invitation(text): return text
        }
    }

    var isTest: Bool {
        if case .test = self { return true }
        return false
    }

    /// The bare recovery token a later referral claim carries: the code without
    /// its prefix. Nil for a test code, which has none.
    var recoveryToken: String? {
        switch self {
        case let .live(text): return String(text.dropFirst(Self.livePrefix.count))
        case let .invitation(token): return token
        case .test: return nil
        }
    }

    /// When the code stops being worth sending. Read from the token body where
    /// it carries one, and otherwise `now` plus the lifetime of its kind.
    func expiresAt(now: Date) -> Date {
        switch self {
        case .live:
            let expiry = recoveryToken.flatMap(ReferralInvitation.parse)?.expiresAt
            return expiry ?? now.addingTimeInterval(Self.liveLifetime)
        case let .invitation(token):
            return ReferralInvitation.parse(token)?.expiresAt ?? now
        case .test:
            return now.addingTimeInterval(Self.testLifetime)
        }
    }

    private static func hasBody(_ text: String, after prefix: String) -> Bool {
        text.hasPrefix(prefix) && text.count > prefix.count
    }
}
