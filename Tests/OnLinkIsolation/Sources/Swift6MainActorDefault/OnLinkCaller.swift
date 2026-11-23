import WarpLink

// Every declaration in this module is main-actor isolated by default, so the
// router and the functions below need no annotation.
final class Router {
    var routed: [WarpLinkDeepLink] = []

    func route(_ result: Result<WarpLinkDeepLink?, WarpLinkError>) {
        if case let .success(link?) = result { routed.append(link) }
    }
}

let router = Router()

let apiKey = "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"

func configureWithClosure() {
    WarpLink.configure(
        apiKey: apiKey,
        options: WarpLinkOptions(onLink: { result in
            router.route(result)
        })
    )
}

func configureWithFunction() {
    WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(onLink: route))
}

func route(_ result: Result<WarpLinkDeepLink?, WarpLinkError>) {
    router.route(result)
}
