import Foundation

/// The single entry point the React Native bridge resolves every tap through.
///
/// Gated by `@_spi(ReactNative)` rather than made public: this is not an
/// alternative to `handleDeepLink(_:completion:)` for a Swift host, it is the
/// bridge's own primitive, reached with `@_spi(ReactNative) import WarpLink`.
///
/// Kept out of `WarpLink+Resolve.swift`, which is already past the file's line
/// budget, and out of `WarpLink+Supersede.swift`, which is the generation
/// primitive rather than an entry point that uses it.
extension WarpLink {

    /// Resolve `url` for the React Native bridge, superseding and cancelling
    /// whatever the bridge's own previous resolve still has on the wire.
    ///
    /// JavaScript (`WarpLink.ts`) owns all dispatch for a React Native host and
    /// calls the bridge's one native `handleDeepLink` method for every tap it
    /// decides to resolve, automatic or manual (`WarpLink.handleDeepLink` from
    /// JS), because the bridge exposes a single method for both. So unlike the
    /// public `handleDeepLink(_:completion:)`, which is never superseded because
    /// it is owed its own answer, a second call HERE always supersedes the
    /// first: there is no manual caller on this path to protect from
    /// cancellation, only whichever call is newest. Matches the Android bridge,
    /// whose shared `resolveDeepLink` cancels on every call the same way
    /// (`LinkResolver.kt`).
    ///
    /// The superseded call's own promise still has to settle: JS is awaiting it
    /// and would otherwise hang forever. So, unlike `open()`, nothing here drops
    /// the completion for a superseded generation. `performResolve`'s
    /// completion already fires exactly once regardless of `isCurrentTap` (see
    /// `deliverResolved`), and that is passed straight through unmodified. A
    /// cancelled attempt still on the wire settles through the normal
    /// retry-exhausted path with `.networkError(URLError.cancelled)`, which the
    /// bridge maps to `E_NETWORK_ERROR`, the same code Android's own
    /// cancellation produces for a network that never actually failed
    /// (warplink-3f0f).
    @_spi(ReactNative)
    public static func resolveFromReactNativeBridge(
        _ url: URL,
        completion: @escaping (Result<WarpLinkDeepLink, WarpLinkError>) -> Void
    ) {
        let generation = supersedeInFlightTap()
        performResolve(url, generation: generation, completion: completion)
    }
}
