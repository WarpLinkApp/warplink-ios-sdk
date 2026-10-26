#if canImport(UIKit)
import UIKit

/// The system paste control for a WarpLink invitation, for UIKit.
///
/// The system shows its own paste prompt only when the person taps this
/// control, so the app never reads the pasteboard on its own. A tap hands the
/// pasted text to `WarpLink.redeemInvitation(text:completion:)`.
///
/// Add it to a view, give it a size, and set `onResult`. Onboarding must stay
/// open when the person skips it, when the copy failed, or when the clipboard
/// holds something else.
@available(iOS 16.0, *)
public final class WarpLinkUIPasteButton: UIView {

    /// Called on the main thread with the outcome of each tap.
    public var onResult: ((Result<WarpLinkDeepLink?, WarpLinkError>) -> Void)?

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
        guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            report(.success(nil))
            return
        }
        _ = provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
            guard let text = object as? String else {
                DispatchQueue.main.async { self?.report(.success(nil)) }
                return
            }
            DispatchQueue.main.async {
                WarpLink.redeemInvitation(text: text) { self?.report($0) }
            }
        }
    }

    private func report(_ result: Result<WarpLinkDeepLink?, WarpLinkError>) {
        onResult?(result)
    }
}
#endif
