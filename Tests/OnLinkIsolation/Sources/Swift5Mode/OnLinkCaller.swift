import WarpLink

/// How an app sets `onLink`. The router touches UI state, so it is `@MainActor`
/// and the handler calls it directly. `handle` is a plain function that is not
/// main-actor isolated, as in an app written before handlers could be.
@MainActor
final class Router {
    var routed: [WarpLinkDeepLink] = []

    func route(_ result: Result<WarpLinkDeepLink?, WarpLinkError>) {
        if case let .success(link?) = result { routed.append(link) }
    }
}

enum App {
    @MainActor static let router = Router()

    static let apiKey = "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"

    static func configureWithClosure() {
        WarpLink.configure(
            apiKey: apiKey,
            options: WarpLinkOptions(onLink: { result in
                router.route(result)
            })
        )
    }

    static func configureWithFunction() {
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(onLink: handle))
    }

    static func handle(_ result: Result<WarpLinkDeepLink?, WarpLinkError>) {
        print(result)
    }
}
