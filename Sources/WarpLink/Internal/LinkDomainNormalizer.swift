import Foundation

/// Reduces a link domain a developer wrote by hand to the exact host spelling
/// the SDK compares `URL.host` against.
///
/// A developer supplies whatever is at hand: the full link copied out of the
/// dashboard, a host with the scheme still attached, a stray capital, a trailing
/// slash. Those all name the same host, and rejecting them would leave the SDK
/// blind to a custom domain on the one launch that has no server answer to fall
/// back on, which is exactly the case this exists to close.
///
/// The rules are plain string operations rather than `URL` parsing on purpose.
/// `URL` disagrees with Android's `Uri` on schemeless and malformed input (a
/// bare `host:8443` parses as a scheme on one side and a host on the other), and
/// both SDKs have to fold the same input to the same host or a developer's
/// domain works on one platform only.
///
/// This is a line-for-line mirror of `normalizeLinkDomain` in the Android SDK,
/// down to the order of the steps. The first version of the two drifted on five
/// inputs while both files claimed the other asserted the same table, so the
/// golden table in the tests is now genuinely identical on both sides and is the
/// thing that holds them together. Change one, change both, and add the row.
enum LinkDomainNormalizer {

    /// Every code point stripped from the ends of a declared domain, listed
    /// explicitly. Swift's whitespacesAndNewlines and Kotlin's trim() disagree:
    /// Swift strips U+200B and U+0085 and keeps U+001C to U+001F, Kotlin does the
    /// opposite. A domain pasted with a zero-width space on its end therefore
    /// matched on one platform and never on the other. The same list, character
    /// for character, lives in LinkDomainNormalization.kt as TRIM_SET.
    private static let trimSet: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: Unicode.Scalar(UInt32(0x09))!...Unicode.Scalar(UInt32(0x0D))!)
        set.insert(charactersIn: Unicode.Scalar(UInt32(0x2000))!...Unicode.Scalar(UInt32(0x200A))!)
        for value: UInt32 in [0x20, 0x85, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
                              0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF] {
            set.insert(Unicode.Scalar(value)!)
        }
        return set
    }()

    /// The host of one entry, or `nil` when the entry names no host.
    ///
    /// Note that `www.` is preserved: `www.example.com` and `example.com` are
    /// different hosts, and iOS hands the app whichever one the link used.
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: Self.trimSet).lowercased()
        if trimmed.isEmpty { return nil }

        let authority = stripScheme(trimmed).prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        let host = stripPort(stripUserInfo(String(authority)))
        return host.isEmpty ? nil : host
    }

    /// Normalize a whole declaration, dropping entries that name no host and
    /// collapsing spellings that fold to the same one.
    static func normalizeAll(_ raw: [String]) -> Set<String> {
        Set(raw.compactMap { normalize($0) })
    }

    // MARK: - Private

    /// Drop `https://`, and the protocol-relative `//` form a copied href can
    /// carry.
    private static func stripScheme(_ value: String) -> String {
        if let separator = value.range(of: "://") {
            return String(value[separator.upperBound...])
        }
        if value.hasPrefix("//") { return String(value.dropFirst(2)) }
        return value
    }

    /// Drop `user:pw@`. Without this the credentials become the host: a pasted
    /// `https://user:pw@links.example.com/` would declare the domain `user`, and
    /// the developer's real domain would never match.
    private static func stripUserInfo(_ authority: String) -> String {
        guard let at = authority.lastIndex(of: "@") else { return authority }
        return String(authority[authority.index(after: at)...])
    }

    /// Drop a `:443` style port. `URL.host` never returns one, so a declared
    /// host that kept its port could never match.
    ///
    /// Only when what follows the last colon is all ASCII digits, so an IPv6
    /// literal and a value that is not a URL at all are left intact rather than
    /// truncated. ASCII specifically, because Swift's `isNumber` and Kotlin's
    /// `isDigit` disagree about other scripts and this has to fold identically.
    private static func stripPort(_ host: String) -> String {
        guard let colon = host.lastIndex(of: ":") else { return host }
        let port = host[host.index(after: colon)...]
        guard !port.isEmpty, port.allSatisfy({ $0.isASCII && $0.isNumber }) else { return host }
        return String(host[..<colon])
    }
}
