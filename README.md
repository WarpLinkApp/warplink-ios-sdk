# WarpLink iOS SDK

[![CI](https://github.com/WarpLinkApp/warplink-ios-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/WarpLinkApp/warplink-ios-sdk/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Deep linking SDK for iOS — resolve Universal Links, handle deferred deep links, and attribute installs with [WarpLink](https://warplink.app).

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
    .package(url: "https://github.com/WarpLinkApp/warplink-ios-sdk", from: "0.1.0")
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

### 1. Configure the SDK

**SwiftUI:**

```swift
import SwiftUI
import WarpLink

@main
struct MyApp: App {
    init() {
        WarpLink.configure(apiKey: "wl_live_your_api_key_here_abcdefgh")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**UIKit:**

```swift
import UIKit
import WarpLink

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        WarpLink.configure(apiKey: "wl_live_your_api_key_here_abcdefgh")
        return true
    }
}
```

### 2. Handle Universal Links

**SwiftUI:**

```swift
ContentView()
    .onOpenURL { url in
        WarpLink.handleDeepLink(url) { result in
            switch result {
            case .success(let deepLink):
                // Route to content using deepLink.destination or deepLink.deepLinkUrl
                print("Deep link: \(deepLink.destination)")
            case .failure(let error):
                print("Error: \(error.localizedDescription)")
            }
        }
    }
```

**UIKit (SceneDelegate):**

```swift
func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    guard let url = userActivity.webpageURL else { return }

    WarpLink.handleDeepLink(url) { result in
        switch result {
        case .success(let deepLink):
            // Route to content
            print("Deep link: \(deepLink.destination)")
        case .failure(let error):
            print("Error: \(error.localizedDescription)")
        }
    }
}
```

### 3. Check for Deferred Deep Links

Call on first launch to check if the user arrived via a link they clicked before installing:

```swift
WarpLink.checkDeferredDeepLink { result in
    switch result {
    case .success(let deepLink):
        if let deepLink = deepLink {
            // User came from a WarpLink — route to content
            print("Deferred deep link: \(deepLink.destination)")
        } else {
            // No deferred deep link — show default onboarding
        }
    case .failure(let error):
        print("Error: \(error.localizedDescription)")
    }
}
```

## Features

- **Universal Link Handling** — resolve incoming links to destinations and custom parameters. See the [Integration Guide](docs/integration-guide.md).
- **Deferred Deep Links** — route users to specific content even after App Store install. See [Deferred Deep Links](docs/deferred-deep-links.md).
- **Install Attribution** — deterministic (IDFV) and probabilistic (fingerprint) matching with confidence scores. See [Attribution](docs/attribution.md).
- **No ATT Required** — uses IDFV (exempt from App Tracking Transparency), no IDFA, no user prompts.
- **Debug Logging** — enable with `WarpLinkOptions(debugLogging: true)` to trace SDK behavior.
- **Zero Dependencies** — built entirely on Apple frameworks (Foundation, UIKit).

## Documentation

| Guide | Description |
|-------|-------------|
| [Integration Guide](docs/integration-guide.md) | Step-by-step setup from zero to working deep links |
| [API Reference](docs/api-reference.md) | Complete reference for all public types and methods |
| [Deferred Deep Links](docs/deferred-deep-links.md) | How deferred deep linking works and how to use it |
| [Attribution](docs/attribution.md) | Install attribution tiers and confidence scores |
| [Error Handling](docs/error-handling.md) | Every error case with recommended recovery actions |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and solutions |
| [Firebase Migration](docs/firebase-migration.md) | Migrate from Firebase Dynamic Links to WarpLink |
| [Architecture](docs/architecture.md) | How the SDK communicates with the WarpLink platform |

## Links

- [WarpLink Dashboard](https://warplink.app)
- [Changelog](CHANGELOG.md)

## License

MIT License. See [LICENSE](LICENSE) for details.
