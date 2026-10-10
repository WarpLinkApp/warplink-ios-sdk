# Integration Guide

Step-by-step guide to integrate the WarpLink iOS SDK. The SDK is opt-out: a single `configure(apiKey:options:)` with an `onLink` sink turns on deep linking, deferred deep linking, and attribution. You add one host hook to deliver incoming Universal Links. No method swizzling.

## Prerequisites

- iOS 15+, Swift 5.9+, Xcode 15+
- A physical iOS device (Universal Links do not work on the iOS Simulator)

## Step 1: Create a WarpLink Account

Sign up at [warplink.app](https://warplink.app). The free tier includes 10,000 clicks per month.

## Step 2: Register Your iOS App

1. In the WarpLink dashboard, go to **Apps**
2. Click **Register App** and select **iOS**
3. Fill in your app details:
   - **Bundle ID** (e.g., `com.yourcompany.yourapp`)
   - **Team ID** (found in Apple Developer portal under Membership)
   - **App Store URL** (or leave blank during development)
4. Save the app. WarpLink generates the Apple App Site Association (AASA) file automatically.

## Step 3: Create an SDK Key

WarpLink issues two kinds of credentials. Mobile apps need an **SDK key**, which is pre-scoped for link resolution and install attribution. API keys are for backend scripts, CI, and AI agents, and they cannot record installs.

1. Go to **API Keys** in the dashboard
2. Click **SDK key**
3. Name it (for example, `iOS production`) and click **Create SDK Key**
4. Copy the key. It is shown once, so store it securely

> **Using an API key here is the most common setup mistake.** Deep links still resolve, so the integration looks healthy, but every attribution call is rejected and no installs appear in your dashboard.

## Step 4: Install the SDK

### Xcode UI

1. In Xcode, go to **File > Add Package Dependencies...**
2. Enter: `https://github.com/WarpLinkApp/warplink-ios-sdk`
3. Select **Up to Next Major Version** and click **Add Package**

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/WarpLinkApp/warplink-ios-sdk", from: "1.1.1")
]
```

## Step 5: Add Associated Domains Entitlement

### In Xcode

1. Select your app target
2. Go to **Signing & Capabilities**
3. Click **+ Capability** and add **Associated Domains**
4. Add the domain: `applinks:aplnk.to`
5. If you use a **custom WarpLink domain**, add it too, e.g. `applinks:go.yourbrand.com`

### In Apple Developer Portal

1. Go to [developer.apple.com](https://developer.apple.com) > **Certificates, Identifiers & Profiles**
2. Select your App ID
3. Enable **Associated Domains** capability
4. Regenerate your provisioning profile if needed

> **Using a custom domain? Declare it.** The SDK also fetches your org's verified
> link domains on `configure()`, but that answer arrives over the network, and a
> link can arrive first: on a first launch, or on any launch that has never
> reached the server. Declaring the domain locally makes it usable the moment
> `configure()` returns.
>
> Either pass it in code:
>
> ```swift
> WarpLinkOptions(linkDomains: ["links.yourbrand.com"], onLink: handleLink)
> ```
>
> or add a `WarpLinkDomains` array of strings to your Info.plist:
>
> ```xml
> <key>WarpLinkDomains</key>
> <array>
>     <string>links.yourbrand.com</string>
> </array>
> ```
>
> Both are optional and additive: `aplnk.to` and the server's list keep working
> either way. List each domain in the Associated Domains entitlement above as
> well, or iOS will not open your app for it in the first place.

## Step 6: Configure the SDK

Initialize the SDK once, as early as possible, with a single `onLink` sink. That sink receives every resolved link: cold-start, warm-start, and deferred (first-install). The deferred check fires automatically.

**SwiftUI:**

```swift
import SwiftUI
import WarpLink

@main
struct MyApp: App {
    init() {
        WarpLink.configure(
            apiKey: "wl_live_yoursdkkeyhere000000000000000000",
            options: WarpLinkOptions(onLink: handleLink)
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { WarpLink.open($0) }   // the one host hook
        }
    }

    func handleLink(_ result: Result<WarpLinkDeepLink?, WarpLinkError>) {
        switch result {
        case .success(let deepLink?):
            navigate(to: deepLink)                  // cold, warm, or deferred
        case .success(nil):
            break                                   // never reaches onLink: a deferred no-match is not dispatched
        case .failure(let error):
            print("WarpLink error: \(error.localizedDescription)")
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
        WarpLink.configure(
            apiKey: "wl_live_yoursdkkeyhere000000000000000000",
            options: WarpLinkOptions(onLink: handleLink)
        )
        return true
    }
}
```

Enable debug logging while integrating:

```swift
WarpLink.configure(
    apiKey: "wl_live_yoursdkkeyhere000000000000000000",
    options: WarpLinkOptions(debugLogging: true, onLink: handleLink)
)
```

> The match window (how far back the server looks for a click) is server-side, set per link in the dashboard. There is no client-side match-window setting.

## Step 7: Deliver Universal Links (one host hook)

When a user taps a WarpLink URL and your app is installed, iOS opens your app with the URL. Hand it to the SDK with one line. The SDK resolves it and delivers the result to `onLink`.

**SwiftUI:**

```swift
ContentView()
    .onOpenURL { WarpLink.open($0) }
```

**UIKit (AppDelegate):**

```swift
func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
) -> Bool {
    WarpLink.continue(userActivity)
}
```

**UIKit (SceneDelegate):**

```swift
func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    WarpLink.continue(userActivity)
}
```

### Zero-code option: provided delegates

If you don't have your own delegate logic, set `WarpLinkAppDelegate` or `WarpLinkSceneDelegate` as your delegate (or subclass it). They forward `continue`/`open` to the SDK for you. No swizzling is performed.

```swift
class SceneDelegate: WarpLinkSceneDelegate {
    // Cold launch, warm continue, and URL contexts are already forwarded.
    // Add your own scene lifecycle code as needed.
}
```

The SDK adds a light dedupe, so if both a provided delegate and your own code deliver the same URL, it is only dispatched once.

## Step 8: Deferred Deep Links (automatic)

Deferred deep links work when a user clicks a WarpLink URL, installs your app from the App Store, and opens it for the first time. The SDK matches the install back to the original click.

**This is automatic.** With default options, `configure()` runs the deferred check on first launch and delivers a match to `onLink` with `isDeferred == true`. A deferred no-match is suppressed, not dispatched to the sink. You don't call anything.

If you disabled `autoDeferredCheck`, run it yourself:

```swift
WarpLink.checkDeferredDeepLink { result in
    if case .success(let deepLink?) = result {
        navigate(to: deepLink)
    }
}
```

See [Deferred Deep Links](deferred-deep-links.md) for the attempt/retry and reinstall behavior.

## Step 9: Create a Test Link

### Via Dashboard

1. Go to **Links** in the WarpLink dashboard
2. Click **Create Link**
3. Set the destination URL (e.g., `https://yourapp.com/product/123`)
4. Optionally set an iOS deep link URL (e.g., `myapp://product/123`)
5. Copy the generated short link (e.g., `https://aplnk.to/abc123`)

### Via API

The REST API takes an **API key** with `links:write`, not the SDK key from Step 3.

```bash
curl -X POST https://api.warplink.app/v1/links \
  -H "Authorization: Bearer wl_live_YOUR_API_KEY" \
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
3. Tap the link: your app should open and `onLink` should fire
4. Check the Xcode console for `[WarpLink]` log messages if you enabled `debugLogging`

### Testing Deferred Deep Links

The completion marker is scoped to one install, so deleting the app is enough to reset the check. (A simulator is fine here. The deferred match is a server-side signal match, not a Universal Link, so it does not need the physical device the tap test above does.)

1. Delete the app from the device or simulator
2. Open the test link in Safari on that device. You will be redirected to the App Store (or a fallback URL during development)
3. Install the app via Xcode (or TestFlight)
4. Launch the app. `onLink` fires with a deferred match (`isDeferred == true`)

To run the test again, repeat from step 1. Every run after the first is reported to the server with `is_reinstall: true`, which does not change what your app receives. See [Troubleshooting](troubleshooting.md#first-launch-already-completed).

### Debugging Tips

- Enable debug logging: `WarpLinkOptions(debugLogging: true)`
- Check Xcode console for `[WarpLink]` prefixed messages. An invalid or revoked SDK key logs a `[WarpLink] WARNING:` line even without debug logging, and `WarpLink.isApiKeyValid` reflects the server verdict.
- Links resolving but no installs in the dashboard usually means an API key was passed to `configure()` instead of an SDK key. An API key passes validation and resolves links, but attribution is rejected. Redo Step 3.
- Verify AASA is served correctly: `curl https://aplnk.to/.well-known/apple-app-site-association`
- See [Troubleshooting](troubleshooting.md) for common issues

## Next Steps

- [API Reference](api-reference.md): full documentation of all public types and methods
- [Error Handling](error-handling.md): how to handle every error case
- [Attribution](attribution.md): understanding signals, confidence scores, and match types
