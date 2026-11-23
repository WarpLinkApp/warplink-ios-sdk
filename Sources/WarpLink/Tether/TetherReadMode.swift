import Foundation

/// How the SDK reads a Tether code from the clipboard.
///
/// The default is `pasteButton`: the SDK never reads the clipboard itself, and
/// the person hands over the code with the system paste control
/// (`WarpLinkPasteButton`, `WarpLinkUIPasteButton`). The raw value is the name
/// the server records.
public enum TetherReadMode: String, Sendable, CaseIterable {

    /// The person taps the system paste control. No prompt appears for the app.
    case pasteButton = "paste_button"

    /// The SDK reads the clipboard once during the first-launch attribution
    /// check. iOS may show its paste prompt at that moment.
    case automatic

    /// The SDK reads the clipboard only when the app calls
    /// `WarpLink.readTether(completion:)`.
    case onCall = "on_call"
}
