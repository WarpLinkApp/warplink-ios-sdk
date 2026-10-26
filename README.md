# WarpLink iOS SDK

[![CI](https://github.com/WarpLinkApp/warplink-ios-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/WarpLinkApp/warplink-ios-sdk/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Deep linking, deferred deep linking, install attribution, and real-time analytics for iOS, with [WarpLink](https://warplink.app). Zero third-party dependencies.

Opt-out by default: a single `configure(apiKey:options:)` with an `onLink` sink turns on deep linking, deferred deep linking, and attribution. You add one host hook to deliver incoming Universal Links. No method swizzling.

## Requirements

- iOS 15+
- Swift 5.9+
- Xcode 15+

## Installation

### Swift Package Manager (Xcode)

1. In Xcode, go to **File > Add Package Dependencies...**
2. Enter the repository URL: `https://github.com/WarpLinkApp/warplink-ios-sdk`
3. Select **Up to Next Major Version** and click **Add Package**

### Swift Package Manager (Package.swift)

```swift
dependencies: [
    .package(url: "https://github.com/WarpLinkApp/warplink-ios-sdk", from: "1.2.0")
]
```

Then add `"WarpLink"` to your target's dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: ["WarpLink"]
)
```

## Quick Start

Everything is on by default. Configure once with a single `onLink` sink, then add one host hook to hand the SDK incoming links.

### 1. Configure with one sink

`onLink` receives every resolved link: cold-start, warm-start, and deferred (first-install). Tell them apart with `deepLink.isDeferred`. Only a real match or an error reaches `onLink`; a deferred check that finds no match is suppressed and never dispatched to the sink. A background deferred check that cannot finish, for example on a launch with no network, retries by itself on the next launch.

```swift
import SwiftUI
import WarpLink

@main
struct MyApp: App {
    init() {
        WarpLink.configure(
            apiKey: "wl_live_yoursdkkeyhere000000000000000000",
            options: WarpLinkOptions(onLink: { result in
                switch result {
                case .success(let deepLink?):
                    route(to: deepLink)          // cold-start, warm-start, or deferred
                case .success(nil):
                    break                        // no link to route; deferred no-match is not dispatched here
                case .failure(let error):
                    print("WarpLink error: \(error.localizedDescription)")
                }
            })
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { WarpLink.open($0) }   // the one host hook
        }
    }
}
```

`apiKey` takes an **SDK key**, created in the dashboard under **Keys** > **SDK keys**. API keys are a different credential: they resolve deep links but cannot record installs, so attribution fails silently if you paste one here.

The deferred deep link check fires automatically from `configure()`. There is nothing else to call for first-install attribution.

### 2. Deliver incoming Universal Links (one hook)

Pick whichever fits your app. All are one line.

**SwiftUI:**

```swift
.onOpenURL { WarpLink.open($0) }
```

**UIKit AppDelegate**: call the one-liner, or subclass the provided delegate:

```swift
func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
) -> Bool {
    WarpLink.continue(userActivity)
}
```

**UIKit SceneDelegate:**

```swift
func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    WarpLink.continue(userActivity)
}
```

Prefer zero code? Set `WarpLinkAppDelegate` / `WarpLinkSceneDelegate` as your delegate (or subclass it) and the forwarding is done for you. See the [Integration Guide](docs/integration-guide.md).

## Turning pieces off

Every feature is opt-out via `WarpLinkOptions`:

```swift
WarpLinkOptions(
    autoDeepLinkHandling: false,  // don't auto-resolve links from open()/continue(); use handleDeepLink instead
    autoDeferredCheck: false,     // don't auto-run the deferred check; call checkDeferredDeepLink yourself
    onLink: nil                   // no single sink; use the per-call completion handlers
)
```

The manual methods remain for advanced use:

- `WarpLink.handleDeepLink(_:completion:)`: resolve a URL and get the result inline.
- `WarpLink.checkDeferredDeepLink(completion:)`: run the deferred check on demand.
- `WarpLink.isWarpLinkURL(_:)` returns whether a URL is a WarpLink link, without resolving it.

### Checking a URL before you route it

If your app has its own router and forwards every incoming URL, ask first:

```swift
if WarpLink.isWarpLinkURL(url) {
    WarpLink.handleDeepLink(url) { result in /* ... */ }
} else {
    myRouter.handle(url)
}
```

`isWarpLinkURL(_:)` is the same check `WarpLink.open(_:)` makes: a host in the known link-domain set, and a path that carries a slug. It resolves nothing and touches no network, so it is safe to call on every URL. Declare your own domain in `WarpLinkOptions.linkDomains` or your Info.plist and `isWarpLinkURL(_:)` recognizes it.

## Features

- **Universal Link handling** with custom-domain support. Declare your domain in `WarpLinkOptions.linkDomains` or a `WarpLinkDomains` Info.plist array and it resolves from the first launch. See the [Integration Guide](docs/integration-guide.md).
- **Deferred deep links**: route users to specific content even after an App Store install, with an attempt/retry model that survives an offline launch and runs again after a reinstall. See [Deferred Deep Links](docs/deferred-deep-links.md).
- **Install attribution**: server-side probabilistic matching with confidence scores, plus an IDFV repeat check that recognizes an install asking again. See [Attribution](docs/attribution.md).
- **No ATT required**: uses IDFV (exempt from App Tracking Transparency), no IDFA, no prompts.
- **No swizzling**: you keep control of your delegates; the SDK never patches `UIApplication`.
- **Zero dependencies**: built entirely on Apple frameworks (Foundation, UIKit, Security).

## Documentation

| Guide | Description |
|-------|-------------|
| [Integration Guide](docs/integration-guide.md) | Step-by-step setup from zero to working deep links |
| [API Reference](docs/api-reference.md) | Complete reference for all public types and methods |
| [Deferred Deep Links](docs/deferred-deep-links.md) | How deferred deep linking works and how to use it |
| [Attribution](docs/attribution.md) | Install attribution tiers, signals, and confidence scores |
| [Error Handling](docs/error-handling.md) | Every error case with recommended recovery actions |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and solutions |
| [Firebase Migration](docs/firebase-migration.md) | Migrate from Firebase Dynamic Links to WarpLink |
| [Architecture](docs/architecture.md) | How the SDK communicates with WarpLink |

## Links

- [WarpLink Dashboard](https://warplink.app)
- [Changelog](CHANGELOG.md)

## License

MIT License. See [LICENSE](LICENSE) for details.
