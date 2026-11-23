import Foundation

/// Turns clipboard text into a code or a reason there is none. The text of a
/// miss is dropped here: it is not sent, stored or logged.
enum TetherReader {

    enum Reading {
        case code(TetherClaim)
        case miss(TetherMissReason)
    }

    /// Reads the clipboard once. A build with no clipboard reads nothing and
    /// answers `olderSdk`. Blocks while the system paste prompt is up, so
    /// call it off the main thread. Only the SDK's own read modes call this.
    static func read(_ clipboard: TetherClipboard) -> Reading {
        guard clipboard.canRead else { return .miss(.olderSdk) }
        guard clipboard.hasStrings else { return .miss(.clipboardEmpty) }
        // Taken before the read, so a copy that lands during the prompt leaves
        // the stamp stale and the clipboard alone.
        let stamp = clipboard.changeCount
        guard let text = clipboard.readString() else { return .miss(.pasteNotAllowed) }
        return reading(of: text, stamp: stamp)
    }

    /// The reading for text a paste control handed over. No read happens.
    /// `acceptingInvitation` lets an unprefixed invitation through, for the
    /// paste button that reports the older invitation result.
    static func reading(of text: String?, stamp: Int?, acceptingInvitation: Bool = false) -> Reading {
        guard let text = text, let code = TetherCode.parse(text, acceptingInvitation: acceptingInvitation) else {
            return .miss(.clipboardEmpty)
        }
        return .code(TetherClaim(code: code, changeCount: stamp))
    }
}
