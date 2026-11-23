#if canImport(SwiftUI)
import SwiftUI

/// The system paste button for a WarpLink Tether code or invitation, for
/// SwiftUI. It is the default way the SDK gets a code.
///
/// The system shows its own paste prompt only when the person taps this
/// button, so the app never reads the pasteboard on its own. On iOS the button
/// is Apple's `UIPasteControl` and its look is the system's. A tap hands the
/// pasted text to the SDK, which sends it only if it is a WarpLink code, and
/// clears the pasteboard once the server has used the code and the pasteboard
/// has not changed since the tap.
///
/// ```swift
/// WarpLinkPasteButton { result in
///     // .failure carries a message that says how to open the link again.
///     // .success(nil): nothing was confirmed. Let the person continue.
/// }
/// ```
///
/// Use `init(onResult:onTether:)` with `onTether` to learn why nothing arrived,
/// or to see a test code. That button sends `wl1_` and `wl1t_` codes only; give
/// it `onResult` as well to keep accepting an older invitation. Onboarding must
/// stay open when the person skips this button, when the copy failed, or when
/// the clipboard holds something else.
@available(iOS 16.0, macOS 13.0, *)
public struct WarpLinkPasteButton: View {

    private let onResult: ((Result<WarpLinkDeepLink?, WarpLinkError>) -> Void)?
    private let onTether: ((Result<TetherReadResult, WarpLinkError>) -> Void)?

    public init(onResult: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void) {
        self.onResult = onResult
        onTether = nil
    }

    /// Reports every tap as a `TetherReadResult`. The label is `onTether`, and
    /// a trailing closure still goes to `init(onResult:)`.
    public init(
        onResult: ((Result<WarpLinkDeepLink?, WarpLinkError>) -> Void)? = nil,
        onTether: @escaping (Result<TetherReadResult, WarpLinkError>) -> Void
    ) {
        self.onResult = onResult
        self.onTether = onTether
    }

    public var body: some View {
        #if canImport(UIKit)
        WarpLinkPasteControl(onResult: onResult, onTether: onTether)
        #else
        PasteButton(payloadType: String.self) { strings in
            WarpLink.redeemPasted(
                text: strings.first, stamp: nil, acceptingInvitation: onResult != nil
            ) { result, detail in
                onResult?(result)
                onTether?(TetherReadResult.make(result, detail: detail))
            }
        }
        #endif
    }
}
#endif
