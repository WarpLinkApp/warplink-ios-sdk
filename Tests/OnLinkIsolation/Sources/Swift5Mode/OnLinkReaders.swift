import WarpLink

/// Code that reads `WarpLinkOptions.onLink` instead of setting it, as an app
/// does when it wraps or forwards the options. It must keep compiling.
enum OnLinkReaders {

    /// Calls the handler from a plain, nonisolated function.
    static func forward(_ options: WarpLinkOptions, _ result: Result<WarpLinkDeepLink?, WarpLinkError>) {
        options.onLink?(result)
    }

    /// Keeps the handler in a `@Sendable` closure variable.
    static func capture(_ options: WarpLinkOptions) -> (@Sendable (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void) {
        let handler: @Sendable (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void = options.onLink!
        return handler
    }
}
