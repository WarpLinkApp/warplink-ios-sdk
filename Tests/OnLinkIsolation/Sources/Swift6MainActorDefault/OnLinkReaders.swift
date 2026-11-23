import WarpLink

// The same two readers as the Swift 5 target. `nonisolated` keeps them out of
// the module's default main-actor isolation, as a utility type in an app is.
enum OnLinkReaders {

    nonisolated static func forward(_ options: WarpLinkOptions, _ result: Result<WarpLinkDeepLink?, WarpLinkError>) {
        options.onLink?(result)
    }

    nonisolated static func capture(
        _ options: WarpLinkOptions
    ) -> (@Sendable (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void) {
        let handler: @Sendable (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void = options.onLink!
        return handler
    }
}
