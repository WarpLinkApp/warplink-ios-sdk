import Foundation

/// The clipboard as the Tether read sees it. Everything that touches the real
/// pasteboard sits behind this, so one file holds the only reference to it and
/// a test can count reads.
protocol TetherClipboard: AnyObject {

    /// False when this build has no clipboard access at all.
    var canRead: Bool { get }

    /// Bumps on every change. Reading it shows no paste prompt.
    var changeCount: Int { get }

    /// Whether the clipboard holds text. Shows no paste prompt.
    var hasStrings: Bool { get }

    /// The text on the clipboard. May show the system paste prompt and wait for
    /// the answer, so call it off the main thread.
    func readString() -> String?

    /// Empties the clipboard. Shows no prompt.
    func clear()
}

/// The clipboard of a platform with no pasteboard.
final class NoClipboard: TetherClipboard {
    let canRead = false
    let changeCount = 0
    let hasStrings = false
    func readString() -> String? { nil }
    func clear() {}
}
