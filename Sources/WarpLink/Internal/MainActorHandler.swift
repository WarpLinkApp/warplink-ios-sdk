import Foundation

/// Turns an `onLink` handler that must run on the main actor into the plain
/// closure `WarpLinkOptions.onLink` stores.
///
/// The stored type stays `@Sendable`, as it was before handlers could be
/// main-actor isolated, so code that reads `options.onLink` and calls it from
/// anywhere still compiles.
enum MainActorHandler {

    typealias Handler = @MainActor @Sendable (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    typealias Plain = @Sendable (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void

    /// Runs `handler` at once when the caller is on the main thread, as the SDK's
    /// own delivery is. From any other thread it hops to the main queue and
    /// never fails.
    static func wrap(_ handler: @escaping Handler) -> Plain {
        { result in
            if Thread.isMainThread {
                MainActor.assumeIsolated { handler(result) }
            } else {
                DispatchQueue.main.async { MainActor.assumeIsolated { handler(result) } }
            }
        }
    }
}
