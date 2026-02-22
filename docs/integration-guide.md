# Integration Guide

Step-by-step guide to integrate the WarpLink iOS SDK into your app. You'll go from zero to working deep links in under 30 minutes.

## Prerequisites

- iOS 15+, Swift 5.9+, Xcode 15+
- A physical iOS device (Universal Links do not work on the iOS Simulator)

## Step 1: Create a WarpLink Account

Sign up at [warplink.app](https://warplink.app). The free tier includes 10,000 clicks per month.

## Step 2: Register Your iOS App

1. In the WarpLink dashboard, go to **Settings > Apps**
2. Click **Add App** and select **iOS**
3. Fill in your app details:
   - **Bundle ID** (e.g., `com.yourcompany.yourapp`)
   - **Team ID** (found in Apple Developer portal under Membership)
   - **App Store URL** (or leave blank during development)
4. Save the app. WarpLink generates the Apple App Site Association (AASA) file automatically.

## Step 3: Create an API Key

1. Go to **Settings > API Keys** in the dashboard
2. Click **Create API Key**
3. Copy your key (format: `wl_live_xxxxxxxxxxxxxxxxxxxxxxxxxxxx`)
4. Store it securely — you'll use this to configure the SDK

## Step 4: Install the SDK

### Xcode UI

1. In Xcode, go to **File > Add Package Dependencies...**
2. Enter: `https://github.com/WarpLinkApp/warplink-ios-sdk`
3. Select **Up to Next Major Version** and click **Add Package**

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/WarpLinkApp/warplink-ios-sdk", from: "0.1.0")
]
```

## Step 5: Add Associated Domains Entitlement

### In Xcode

1. Select your app target
2. Go to **Signing & Capabilities**
3. Click **+ Capability** and add **Associated Domains**
4. Add the domain: `applinks:aplnk.to`

### In Apple Developer Portal

1. Go to [developer.apple.com](https://developer.apple.com) > **Certificates, Identifiers & Profiles**
2. Select your App ID
3. Enable **Associated Domains** capability
4. Regenerate your provisioning profile if needed

> **Note:** WarpLink currently supports the `aplnk.to` domain. Custom domains will be supported in a future SDK update.

## Step 6: Configure the SDK

Initialize the SDK as early as possible in your app lifecycle.

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

You can also pass options for debug logging or a custom match window:

```swift
WarpLink.configure(
    apiKey: "wl_live_your_api_key_here_abcdefgh",
    options: WarpLinkOptions(debugLogging: true, matchWindowHours: 48)
)
```

## Step 7: Handle Universal Links

When a user taps a WarpLink URL and your app is installed, iOS opens your app with the URL. Handle it to resolve the deep link.

**SwiftUI:**

```swift
@main
struct MyApp: App {
    init() {
        WarpLink.configure(apiKey: "wl_live_your_api_key_here_abcdefgh")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    WarpLink.handleDeepLink(url) { result in
                        switch result {
                        case .success(let deepLink):
                            // Route based on destination or deep link URL
                            navigateTo(deepLink.destination)
                        case .failure(let error):
                            print("Error: \(error.localizedDescription)")
                        }
                    }
                }
        }
    }
}
```

**UIKit (SceneDelegate):**

```swift
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let url = userActivity.webpageURL else { return }

        WarpLink.handleDeepLink(url) { result in
            switch result {
            case .success(let deepLink):
                navigateTo(deepLink.destination)
            case .failure(let error):
                print("Error: \(error.localizedDescription)")
            }
        }
    }
}
```

The completion handler is always called on the main thread, so you can safely update UI from it.

## Step 8: Handle Deferred Deep Links

Deferred deep links work when a user clicks a WarpLink URL, installs your app from the App Store, and opens it for the first time. The SDK matches the install back to the original click.

Call `checkDeferredDeepLink` once, early in your app's first-launch flow:

```swift
WarpLink.checkDeferredDeepLink { result in
    switch result {
    case .success(let deepLink):
        if let deepLink = deepLink {
            // User arrived via a WarpLink — route to intended content
            navigateTo(deepLink.destination)
        } else {
            // No deferred deep link — show default onboarding
        }
    case .failure(let error):
        print("Deferred deep link error: \(error.localizedDescription)")
    }
}
```

The SDK automatically detects first launch and caches the result. Subsequent calls return the cached result without a network request.

See [Deferred Deep Links](deferred-deep-links.md) for details on confidence scores and edge cases.

## Step 9: Create a Test Link

### Via Dashboard

1. Go to **Links** in the WarpLink dashboard
2. Click **Create Link**
3. Set the destination URL (e.g., `https://yourapp.com/product/123`)
4. Optionally set an iOS deep link URL (e.g., `myapp://product/123`)
5. Copy the generated short link (e.g., `https://aplnk.to/abc123`)

### Via API

```bash
curl -X POST https://api.warplink.app/v1/links \
  -H "Authorization: Bearer wl_live_your_api_key_here_abcdefgh" \
  -H "Content-Type: application/json" \
  -d '{
    "destination_url": "https://yourapp.com/product/123",
    "ios_url": "myapp://product/123"
  }'
```

## Step 10: Test on a Physical Device

> **Universal Links do not work on the iOS Simulator.** You must test on a physical device.

1. Build and run your app on a physical iOS device
2. Open the test link in Safari on the device (or send it via Messages/Notes)
3. Tap the link — your app should open and the deep link callback should fire
4. Check the Xcode console for `[WarpLink]` log messages if you enabled `debugLogging`

### Testing Deferred Deep Links

1. Delete your app from the test device
2. Open the test link in Safari — you'll be redirected to the App Store (or a fallback URL during development)
3. Install the app via Xcode (or TestFlight)
4. Launch the app — `checkDeferredDeepLink` should return the matched deep link

### Debugging Tips

- Enable debug logging: `WarpLinkOptions(debugLogging: true)`
- Check Xcode console for `[WarpLink]` prefixed messages
- Verify AASA is served correctly: `curl https://aplnk.to/.well-known/apple-app-site-association`
- See [Troubleshooting](troubleshooting.md) for common issues

## Next Steps

- [API Reference](api-reference.md) — full documentation of all public types and methods
- [Error Handling](error-handling.md) — how to handle every error case
- [Attribution](attribution.md) — understanding confidence scores and match types
