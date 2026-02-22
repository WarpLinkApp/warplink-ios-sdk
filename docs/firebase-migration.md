# Firebase Dynamic Links Migration Guide

Firebase Dynamic Links was deprecated on August 25, 2025. This guide walks you through migrating to WarpLink.

## Concept Mapping

| Firebase Dynamic Links | WarpLink |
|----------------------|----------|
| Dynamic Links | Links |
| Firebase console | [WarpLink dashboard](https://warplink.app) |
| `FirebaseCore` + `FirebaseDynamicLinks` SDKs | `WarpLink` SDK (single package) |
| `yourapp.page.link` domain | `aplnk.to` domain |
| `DynamicLinks.dynamicLinks()` | `WarpLink` (static methods) |
| Link parameters (social metadata, analytics) | Link fields (destination, iOS URL, custom params) |

## Step 1: Recreate Your Links

Recreate your Firebase Dynamic Links as WarpLink links via the [dashboard](https://warplink.app) or the [REST API](https://api.warplink.app/v1).

### Parameter Mapping

| Firebase Parameter | WarpLink Field |
|-------------------|----------------|
| `link` (deep link URL) | `destination_url` |
| `isi` (iOS App Store ID) | Configured per-app in dashboard |
| `ibi` (iOS bundle ID) | Configured per-app in dashboard |
| `ifl` (iOS fallback link) | `ios_fallback_url` |
| `efr` (skip preview page) | N/A (WarpLink uses 302 redirects by default) |
| `st` / `sd` / `si` (social metadata) | OG tags on destination page |
| Custom parameters | `custom_params` JSON object |

### Via Dashboard

1. Go to **Links** > **Create Link**
2. Set the destination URL
3. Add iOS deep link URL if needed (e.g., `myapp://path`)
4. Add any custom parameters

### Via API

```bash
curl -X POST https://api.warplink.app/v1/links \
  -H "Authorization: Bearer wl_live_your_api_key_here_abcdefgh" \
  -H "Content-Type: application/json" \
  -d '{
    "destination_url": "https://yourapp.com/product/123",
    "ios_url": "myapp://product/123",
    "custom_params": { "referrer": "campaign_spring" }
  }'
```

## Step 2: Swap the SDK

### Remove Firebase

1. In Xcode, go to **File > Packages** (or your project's package list)
2. Remove `FirebaseCore` and `FirebaseDynamicLinks` packages
3. Remove `FirebaseApp.configure()` from your app delegate (unless you use other Firebase services)
4. Remove `import FirebaseCore` and `import FirebaseDynamicLinks` from your source files

### Add WarpLink

1. **File > Add Package Dependencies...**
2. Enter: `https://github.com/WarpLinkApp/warplink-ios-sdk`
3. Select **Up to Next Major Version** and click **Add Package**

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/WarpLinkApp/warplink-ios-sdk", from: "0.1.0")
]
```

## Step 3: Update SDK Initialization

**Firebase:**

```swift
import FirebaseCore

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        FirebaseApp.configure()
        return true
    }
}
```

**WarpLink:**

```swift
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

**SwiftUI:**

```swift
import WarpLink

@main
struct MyApp: App {
    init() {
        WarpLink.configure(apiKey: "wl_live_your_api_key_here_abcdefgh")
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

## Step 4: Update Associated Domains

In your Xcode target under **Signing & Capabilities > Associated Domains**:

**Firebase:**
```
applinks:yourapp.page.link
```

**WarpLink:**
```
applinks:aplnk.to
```

Also update the capability in the [Apple Developer portal](https://developer.apple.com) if you manage provisioning profiles manually.

## Step 5: Migrate Deep Link Handling

### Universal Link Handler

**Firebase:**

```swift
func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
) -> Bool {
    let handled = DynamicLinks.dynamicLinks().handleUniversalLink(
        userActivity.webpageURL!
    ) { dynamicLink, error in
        guard error == nil, let link = dynamicLink?.url else { return }
        // Handle the deep link
        self.handleDeepLink(link)
    }
    return handled
}
```

**WarpLink:**

```swift
func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    guard let url = userActivity.webpageURL else { return }

    WarpLink.handleDeepLink(url) { result in
        switch result {
        case .success(let deepLink):
            self.navigateTo(deepLink.destination)
        case .failure(let error):
            print("Error: \(error.localizedDescription)")
        }
    }
}
```

**SwiftUI:**

```swift
ContentView()
    .onOpenURL { url in
        WarpLink.handleDeepLink(url) { result in
            switch result {
            case .success(let deepLink):
                navigateTo(deepLink.destination)
            case .failure(let error):
                print("Error: \(error.localizedDescription)")
            }
        }
    }
```

### Key Differences

| | Firebase | WarpLink |
|-|---------|----------|
| Return type | `DynamicLink?` (optional) | `Result<WarpLinkDeepLink, WarpLinkError>` |
| Deep link URL | `dynamicLink.url` | `deepLink.destination` or `deepLink.deepLinkUrl` |
| Error handling | Separate `error` parameter | `Result.failure` case with typed errors |
| Custom parameters | Embedded in the URL as query params | `deepLink.customParams` dictionary |

## Step 6: Migrate Deferred Deep Links

**Firebase:**

```swift
DynamicLinks.dynamicLinks().dynamicLink(fromCustomSchemeURL: url) { dynamicLink, error in
    guard let link = dynamicLink?.url else { return }
    self.handleDeepLink(link)
}
```

**WarpLink:**

```swift
WarpLink.checkDeferredDeepLink { result in
    switch result {
    case .success(let deepLink):
        if let deepLink = deepLink {
            navigateTo(deepLink.destination)
        }
    case .failure(let error):
        print("Error: \(error.localizedDescription)")
    }
}
```

### Key Differences

| | Firebase | WarpLink |
|-|---------|----------|
| When to call | On app open | On first launch (SDK handles detection) |
| Caching | Manual | Automatic (cached after first check) |
| Attribution data | None | `matchType`, `matchConfidence` |
| Custom params | Via URL query params | `deepLink.customParams` dictionary |

## Step 7: Testing Checklist

After migration, verify each flow works:

- [ ] **SDK initializes** — enable `debugLogging` and check for `[WarpLink] Configured with API key: ...` in the console
- [ ] **API key validates** — check for `[WarpLink] API key validated successfully`
- [ ] **Universal Links open the app** — tap a WarpLink URL on a physical device
- [ ] **Deep link resolves** — `handleDeepLink` returns a `WarpLinkDeepLink` with the correct destination
- [ ] **Custom parameters are preserved** — check `deepLink.customParams` matches what you configured
- [ ] **Deferred deep links work** — delete app, click link, reinstall, launch, verify `checkDeferredDeepLink` returns match
- [ ] **AASA is correct** — `curl https://aplnk.to/.well-known/apple-app-site-association` shows your app's bundle ID and team ID
- [ ] **Error handling works** — test with an invalid URL, expired link, and no connectivity
- [ ] **Old Firebase code is fully removed** — no remaining `import FirebaseCore` or `import FirebaseDynamicLinks`
- [ ] **Build succeeds** — clean build with no Firebase dependencies

## Related Guides

- [Integration Guide](integration-guide.md) — full setup walkthrough
- [API Reference](api-reference.md) — all public types and methods
- [Troubleshooting](troubleshooting.md) — common issues after migration
