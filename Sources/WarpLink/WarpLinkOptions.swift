import Foundation

/// Configuration options for the WarpLink SDK.
///
/// Every feature is on by default (opt-out). A bare `configure(apiKey:)` makes
/// deep linking, deferred deep linking, and attribution work automatically.
public struct WarpLinkOptions: Sendable {
    /// The API endpoint URL.
    public let apiEndpoint: String

    /// Whether to enable debug logging.
    public let debugLogging: Bool

    /// When `true` (default), `WarpLink.open(_:)` / `WarpLink.continue(_:)`
    /// (and the provided host delegates) automatically resolve incoming
    /// Universal Links and deliver the result to `onLink`. Set to `false` to
    /// handle links yourself via `WarpLink.handleDeepLink(_:completion:)`.
    public let autoDeepLinkHandling: Bool

    /// When `true` (default), `configure()` automatically runs the deferred
    /// deep link check on first launch and delivers the result to `onLink`.
    /// Set to `false` to call `WarpLink.checkDeferredDeepLink(completion:)`
    /// yourself.
    public let autoDeferredCheck: Bool

    /// Your WarpLink link domains, e.g. `["links.yourbrand.com"]`. Optional.
    ///
    /// Declaring them here makes them usable the moment `configure()` returns,
    /// which is what a Universal Link arriving on a first launch needs: the
    /// server's list of your verified domains is still on its way, and
    /// `WarpLink.open(_:)` has to answer immediately. Anything you declare is
    /// added to `aplnk.to` and to the server's list, never substituted for
    /// them, so leaving this empty keeps the existing behaviour.
    ///
    /// The alternative to writing it in code is the `WarpLinkDomains` array in
    /// your Info.plist. Both are read, and either accepts a bare host or a full
    /// URL.
    public let linkDomains: [String]

    /// The single sink for all resolved links: cold-start, warm-start, and
    /// deferred. Disambiguate with `WarpLinkDeepLink.isDeferred`. Fires only on
    /// a resolved link or an error; a no-match is not delivered here (uniform
    /// with the Android and React Native SDKs). Call
    /// `checkDeferredDeepLink(completion:)` yourself if you need the no-match
    /// signal.
    public let onLink: (@Sendable (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void)?

    public init(
        apiEndpoint: String = "https://api.warplink.app/v1",
        debugLogging: Bool = false,
        autoDeepLinkHandling: Bool = true,
        autoDeferredCheck: Bool = true,
        linkDomains: [String] = [],
        onLink: (@Sendable (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void)? = nil
    ) {
        self.apiEndpoint = apiEndpoint
        self.debugLogging = debugLogging
        self.autoDeepLinkHandling = autoDeepLinkHandling
        self.autoDeferredCheck = autoDeferredCheck
        self.linkDomains = linkDomains
        self.onLink = onLink
    }
}
