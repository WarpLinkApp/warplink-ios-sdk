#if canImport(SwiftUI)
import SwiftUI

/// The system paste button for a WarpLink invitation, for SwiftUI.
///
/// The system shows its own paste prompt only when the person taps this
/// button, so the app never reads the pasteboard on its own. A tap hands the
/// pasted text to `WarpLink.redeemInvitation(text:completion:)`.
///
/// ```swift
/// WarpLinkPasteButton { result in
///     // .failure carries a message that says how to open the invitation again.
///     // .success(nil): nothing was confirmed. Let the person continue.
/// }
/// ```
///
/// Onboarding must stay open when the person skips this button, when the copy
/// failed, or when the clipboard holds something else.
@available(iOS 16.0, macOS 13.0, *)
public struct WarpLinkPasteButton: View {

    private let onResult: (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void

    public init(onResult: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void) {
        self.onResult = onResult
    }

    public var body: some View {
        PasteButton(payloadType: String.self) { strings in
            guard let text = strings.first else {
                onResult(.success(nil))
                return
            }
            WarpLink.redeemInvitation(text: text, completion: onResult)
        }
    }
}
#endif
