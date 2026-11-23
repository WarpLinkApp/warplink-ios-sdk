#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// `WarpLinkUIPasteButton` for SwiftUI. SwiftUI's own `PasteButton` hands the
/// text over after its read, so a copy made in between would carry the old
/// code's change count. The UIKit control reports the tap first, so the count
/// is taken at the tap.
@available(iOS 16.0, *)
struct WarpLinkPasteControl: UIViewRepresentable {

    let onResult: ((Result<WarpLinkDeepLink?, WarpLinkError>) -> Void)?
    let onTether: ((Result<TetherReadResult, WarpLinkError>) -> Void)?

    func makeUIView(context: Context) -> WarpLinkUIPasteButton {
        let button = WarpLinkUIPasteButton()
        button.onResult = onResult
        button.onTether = onTether
        return button
    }

    func updateUIView(_ button: WarpLinkUIPasteButton, context: Context) {
        button.onResult = onResult
        button.onTether = onTether
    }
}
#endif
