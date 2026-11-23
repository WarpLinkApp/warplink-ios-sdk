#if canImport(UIKit)
import UIKit

/// The system paste control for a WarpLink Tether code or invitation, for
/// UIKit. It is the default way the SDK gets a code.
///
/// The system shows its own paste prompt only when the person taps this
/// control, so the app never reads the pasteboard on its own. The control is
/// Apple's `UIPasteControl`, styled only through the `configuration` you pass.
/// A tap hands the pasted text to the SDK, which sends it only if it is a
/// WarpLink code, and clears the pasteboard once the server has used the code
/// and the pasteboard has not changed since.
///
/// Add it to a view, give it a size, and set `onResult`, or `onTether` to learn
/// why nothing arrived. Onboarding must stay open when the person skips it,
/// when the copy failed, or when the clipboard holds something else.
@available(iOS 16.0, *)
public final class WarpLinkUIPasteButton: UIView {

    /// Called on the main thread with the outcome of each tap.
    public var onResult: ((Result<WarpLinkDeepLink?, WarpLinkError>) -> Void)?

    /// Called on the main thread with each tap, as a `TetherReadResult`.
    public var onTether: ((Result<TetherReadResult, WarpLinkError>) -> Void)?

    private let control: UIPasteControl

    public init(
        configuration: UIPasteControl.Configuration = UIPasteControl.Configuration(),
        onResult: ((Result<WarpLinkDeepLink?, WarpLinkError>) -> Void)? = nil
    ) {
        control = UIPasteControl(configuration: configuration)
        self.onResult = onResult
        super.init(frame: .zero)
        pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
        control.target = self
        control.translatesAutoresizingMaskIntoConstraints = false
        addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: leadingAnchor),
            control.trailingAnchor.constraint(equalTo: trailingAnchor),
            control.topAnchor.constraint(equalTo: topAnchor),
            control.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("WarpLinkUIPasteButton is created in code")
    }

    public override var intrinsicContentSize: CGSize { control.intrinsicContentSize }

    public override func paste(itemProviders: [NSItemProvider]) {
        // Taken at the tap, before the text loads: a copy that lands while it
        // loads must not be cleared.
        let stamp = TetherServices.clipboard.changeCount
        guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            redeem(text: nil, stamp: stamp)
            return
        }
        _ = provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
            DispatchQueue.main.async { self?.redeem(text: object as? String, stamp: stamp) }
        }
    }

    private func redeem(text: String?, stamp: Int) {
        // The older invitation text is taken only for a control that reports
        // the older result; a Tether control sends `wl1_` and `wl1t_` codes only.
        WarpLink.redeemPasted(
            text: text, stamp: stamp, acceptingInvitation: onResult != nil
        ) { [weak self] result, detail in
            self?.onResult?(result)
            self?.onTether?(TetherReadResult.make(result, detail: detail))
        }
    }
}
#endif
