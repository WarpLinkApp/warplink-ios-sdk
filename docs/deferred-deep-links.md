# Deferred Deep Links

Deferred deep links let you route users to specific content even when they don't have your app installed yet. The user clicks a link, installs your app from the App Store, and on first launch the SDK matches them back to the original link.

## What Are Deferred Deep Links?

Standard Universal Links only work when the app is already installed. Deferred deep links solve the "click before install" problem:

1. User clicks a WarpLink URL (e.g., a product share link)
2. App is not installed — user is redirected to the App Store
3. User installs the app
4. On first launch, the SDK matches the install to the original click
5. Your app routes the user to the intended content (e.g., the shared product)

Without deferred deep links, the user would land on your default home screen with no context about what brought them there.

## How It Works

The deferred deep link flow involves 8 steps:

1. **Click** — User taps a WarpLink URL in Safari or another app
2. **Signal capture** — WarpLink's redirect page collects browser signals (IP, User-Agent, Accept-Language, screen size, timezone) via a brief JavaScript interstitial
3. **Store redirect** — User is redirected to the App Store
4. **Install** — User installs and opens the app
5. **First launch detection** — The SDK detects this is the first launch (tracked via UserDefaults)
6. **Fingerprint collection** — The SDK collects device signals: screen size, timezone, preferred languages, and IDFV
7. **Attribution request** — The SDK sends collected signals to `/attribution/match`
8. **Match result** — The server matches against stored click signals and returns a `WarpLinkDeepLink` with `isDeferred: true`

## Confidence Scores

The match confidence depends on the matching method and time elapsed since the click:

| Scenario | Confidence | Match Type |
|----------|------------|------------|
| IDFV re-engagement (app was previously installed) | 1.0 | `deterministic` |
| Enriched fingerprint, < 1 hour since click | 0.85 | `probabilistic` |
| Enriched fingerprint, < 24 hours since click | 0.65 | `probabilistic` |
| Enriched fingerprint, < 72 hours since click | 0.40 | `probabilistic` |
| Multiple candidates matched | -0.15 per additional candidate | `probabilistic` |

**Recommendation:** Route to specific content when `matchConfidence` is above 0.5. Show generic onboarding when below 0.5.

## Match Window Configuration

The match window controls how far back the server looks for matching clicks. Default is 72 hours.

```swift
// Reduce match window to 48 hours for higher accuracy
WarpLink.configure(
    apiKey: "wl_live_your_api_key_here_abcdefgh",
    options: WarpLinkOptions(matchWindowHours: 48)
)
```

A shorter window reduces false positives but may miss users who take longer to install.

## Caching Behavior

- The SDK checks for a deferred deep link only on the first launch.
- The result (match or no match) is cached in UserDefaults.
- Subsequent calls to `checkDeferredDeepLink` return the cached result without a network request.
- This means the attribution check happens exactly once per app install.

## Code Example

```swift
WarpLink.checkDeferredDeepLink { result in
    switch result {
    case .success(let deepLink):
        guard let deepLink = deepLink else {
            // No deferred deep link — show default onboarding
            showOnboarding()
            return
        }

        // Route based on confidence
        let confidence = deepLink.matchConfidence ?? 0

        if confidence > 0.5 {
            // High confidence — route to specific content
            if let deepLinkUrl = deepLink.deepLinkUrl {
                navigateTo(deepLinkUrl)
            } else {
                navigateTo(deepLink.destination)
            }
        } else {
            // Low confidence — show generic welcome with a hint
            showWelcome(suggestedContent: deepLink.destination)
        }

    case .failure(let error):
        // Network error on first launch — show default experience
        // Consider retrying when connectivity is restored
        print("Deferred deep link error: \(error.localizedDescription)")
        showOnboarding()
    }
}
```

## Edge Cases

### Offline First Launch

If the device has no network connectivity on first launch, `checkDeferredDeepLink` will fail with `.networkError`. The first-launch flag will have been consumed, so retrying after connectivity is restored will return the cached `nil` result.

**Recommendation:** If network connectivity is critical for your first-launch experience, check for connectivity before calling `checkDeferredDeepLink`, or implement a retry mechanism that listens for network changes.

### App Reinstall

UserDefaults may persist across app delete/reinstall depending on the iOS version and iCloud backup settings. If UserDefaults persists, the SDK will consider it a subsequent launch and return the previously cached result (or `nil`) instead of performing a new attribution check.

### Multiple Links Clicked Before Install

If a user clicks multiple WarpLink URLs before installing, only the **most recent** click is stored for matching. The server matches against the latest deferred payload for the fingerprint.

## Related Guides

- [Attribution](attribution.md) — detailed explanation of matching tiers
- [Error Handling](error-handling.md) — handling deferred deep link errors
- [Troubleshooting](troubleshooting.md) — common deferred deep link issues
