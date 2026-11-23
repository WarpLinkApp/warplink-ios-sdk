import Foundation

/// Why no Tether code arrived. The raw value is the name the server records.
///
/// This SDK reports `pasteNotAllowed`, `clipboardEmpty` and `olderSdk`. The
/// server sets `expired`, `otherApp` and `linkEnded` when it refuses a code it
/// was sent. `inAppBrowser` is set where the link opened, not on the device.
public enum TetherMissReason: String, Sendable, CaseIterable {
    case pasteNotAllowed = "paste_not_allowed"
    case clipboardEmpty = "clipboard_empty"
    case inAppBrowser = "in_app_browser"
    case expired
    case otherApp = "other_app"
    case linkEnded = "link_ended"
    case olderSdk = "older_sdk"
}
