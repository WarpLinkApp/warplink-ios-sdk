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

    /// How the SDK reads a Tether code from the clipboard. The default,
    /// `.pasteButton`, never reads the clipboard: the person hands the code over
    /// with `WarpLinkPasteButton` or `WarpLinkUIPasteButton`. `.automatic` reads
    /// it once during the first-launch check, and iOS may show its paste prompt.
    /// `.onCall` reads it only when you call `WarpLink.readTether(completion:)`.
    public let tetherReadMode: TetherReadMode

    /// The single sink for all resolved links: cold-start, warm-start, and
    /// deferred. Disambiguate with `WarpLinkDeepLink.isDeferred`. Fires only on
    /// a resolved link or an error; a no-match is not delivered here (uniform
    /// with the Android and React Native SDKs). Call
    /// `checkDeferredDeepLink(completion:)` yourself if you need the no-match
    /// signal.
    ///
    /// The handler you pass to `init` runs on the main actor, so it can call
    /// `@MainActor` code and touch UI without hopping itself. This property is a
    /// plain `@Sendable` closure that does the hop: calling it from the main
    /// thread runs the handler at once, and from any other thread it runs the
    /// handler on the main queue.
    public let onLink: (@Sendable (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void)?

    public init(
        apiEndpoint: String = "https://api.warplink.app/v1",
        debugLogging: Bool = false,
        autoDeepLinkHandling: Bool = true,
        autoDeferredCheck: Bool = true,
        linkDomains: [String] = [],
        tetherReadMode: TetherReadMode = .pasteButton,
        onLink: (@MainActor @Sendable (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void)? = nil
    ) {
        self.apiEndpoint = apiEndpoint
        self.debugLogging = debugLogging
        self.autoDeepLinkHandling = autoDeepLinkHandling
        self.autoDeferredCheck = autoDeferredCheck
        self.linkDomains = linkDomains
        self.tetherReadMode = tetherReadMode
        self.onLink = onLink.map(MainActorHandler.wrap)
    }
}
