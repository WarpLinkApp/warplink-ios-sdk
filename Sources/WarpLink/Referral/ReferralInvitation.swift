import Foundation

/// The invitation the handoff page copies for the user to paste into the app.
///
/// An invitation is exactly one recovery token and nothing else: 37 bytes,
/// written as 50 URL-safe base64 characters without padding. Anything that is
/// not that shape is not an invitation and is never sent anywhere, so pasted
/// text that belongs to something else stays on the device.
///
/// Only the shape and the expiry are read here. The signature and the app the
/// token belongs to are checked by the server, which is the only authority.
struct ReferralInvitation: Equatable {

    /// The token as the user pasted it, trimmed.
    let token: String

    /// When the server stops accepting the token.
    let expiresAt: Date

    private static let encodedLength = 50
    private static let decodedLength = 37
    private static let expiryRange = 16..<20
    private static let alphabet = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    )

    /// The invitation in `text`, or nil when `text` is not one.
    static func parse(_ text: String) -> ReferralInvitation? {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.count == encodedLength,
              candidate.unicodeScalars.allSatisfy({ alphabet.contains($0) }),
              let bytes = decode(candidate),
              bytes.count == decodedLength else { return nil }
        let seconds = bytes[expiryRange].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return ReferralInvitation(
            token: candidate,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(seconds))
        )
    }

    /// Whether the token has run out at `now`. The expiry second itself counts
    /// as expired.
    func isExpired(at now: Date) -> Bool {
        expiresAt <= now
    }

    private static func decode(_ encoded: String) -> Data? {
        let standard = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = String(repeating: "=", count: (4 - standard.count % 4) % 4)
        return Data(base64Encoded: standard + padding)
    }
}
