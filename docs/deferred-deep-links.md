# Deferred Deep Links

Deferred deep links let you route users to specific content even when they don't have your app installed yet. The user clicks a link, installs your app from the App Store, and on first launch the SDK matches them back to the original link.

With default options this is fully automatic: `configure()` runs the check and delivers the result to your `onLink` sink.

## What Are Deferred Deep Links?

Standard Universal Links only work when the app is already installed. Deferred deep links solve the "click before install" problem:

1. User clicks a WarpLink URL (e.g., a product share link)
2. App is not installed: user is redirected to the App Store
3. User installs the app
4. On first launch, the SDK matches the install to the original click
5. Your app routes the user to the intended content (e.g., the shared product)

Without deferred deep links, the user would land on your default home screen with no context about what brought them there.

## How It Works

1. **Click**: User taps a WarpLink URL in Safari or another app
2. **Signal capture**: WarpLink's redirect page records the click's match signals (server-side, from the request) and the click's link
3. **Store redirect**: User is redirected to the App Store
4. **Install**: User installs and opens the app
5. **First launch**: On `configure()`, the SDK collects raw device signals (preferred language, timezone, IDFV) and posts them to `/attribution/match`
6. **Match result**: The server computes the match key (adding the request IP) and returns a `WarpLinkDeepLink` with `isDeferred: true`, delivered to `onLink`

The SDK sends only `accept_language` + `timezone` + `timezone_offset` + `app_bundle_id` + optional `device_id` (IDFV). The `timezone` field is the IANA zone name (e.g. `America/Toronto`), new in 1.1.0; the offset stays as the fallback key for older SDKs. See [Attribution](attribution.md) for the full signal set.

## Automatic vs manual

**Automatic (default).** `autoDeferredCheck` is on, so `configure()` fires the check for you and routes any match to `onLink`. A match arrives with `isDeferred == true`. A no-match is suppressed and not dispatched to the sink; only a real match or an error reaches `onLink`. A delivered result arrives at most once (it is not re-fired on every later launch).

```swift
WarpLink.configure(
    apiKey: "wl_live_yoursdkkeyhere000000000000000000",
    options: WarpLinkOptions(onLink: { result in
        if case .success(let deepLink?) = result, deepLink.isDeferred {
            navigate(to: deepLink)
        }
    })
)
```

**Manual.** Disable `autoDeferredCheck` and call it yourself:

```swift
WarpLink.configure(
    apiKey: "wl_live_yoursdkkeyhere000000000000000000",
    options: WarpLinkOptions(autoDeferredCheck: false)
)

WarpLink.checkDeferredDeepLink { result in
    switch result {
    case .success(let deepLink?):
        navigate(to: deepLink)
    case .success(nil):
        showOnboarding()
    case .failure(let error):
        print("Deferred deep link error: \(error.localizedDescription)")
    }
}
```

## First-launch model: attempt vs complete

The SDK splits the first-launch flag into **attempted** and **completed**:

- An attribution attempt is marked **completed** only on a *definitive server response* (a match or a confirmed no-match).
- If the attempt fails before that (for example, the device is offline on first launch), it is marked **attempted** but not **completed**, so the SDK **retries on the next launch**.

This fixes the classic footgun where an offline first launch silently consumed the one-shot flag and no attribution ever ran.

### Reinstall behavior

A reinstall counts as an install, so attribution runs again on a reinstall.

The completed marker is scoped to one install: it lives in a file that is excluded from iCloud and iTunes backups, so it goes away with the app and does not come back from a restore. Within one install it still guarantees at most one attribution, however many times the app launches.

A second, separate marker in the **Keychain** records only that this device has been attributed at some point. It gates nothing. It survives the delete and the restore, which is how the SDK can tell a reinstall apart from a first install and report `is_reinstall` with the attribution request. Installs and reinstalls are counted together in the dashboard.

## Caching Behavior

- The network attribution call happens once, when the attempt completes.
- The matched result is cached (`WarpLink.attributionResult`), and `checkDeferredDeepLink` returns it without a network call after completion.
- A failed attempt does not cache a result and does not block a retry.

## Confidence Scores

The match confidence depends on the matching method and time elapsed since the click:

| Scenario | Confidence | Match Type |
|----------|------------|------------|
| IDFV repeat check (app was previously installed) | The stored install's own score | The stored install's own type |
| Probabilistic match, < 1 hour since click | 0.85 | `probabilistic` |
| Probabilistic match, < 3 hours since click | 0.65 | `probabilistic` |
| Probabilistic match, < 6 hours since click | 0.50 | `probabilistic` |
| Probabilistic match, < 24 hours since click | 0.30 | `probabilistic` |
| 24 hours or more since click | no match | none |

The probabilistic rows are the ceilings for the zone-name variant that an SDK collecting a zone name sends. The offset variant kept for older SDKs scores a band lower (0.80 down to 0.25), and the language-only fallback lower still (0.70 down to 0.20). Two multipliers then reduce whichever ceiling applied: 0.6 when more than one distinct link shared the match key, and 0.6 / 0.9 / 1.0 for a carrier-grade-NAT, household-IPv4, or IPv6 click address. See [Attribution](attribution.md) for the full tables.

**Recommendation:** Route to specific content when `matchConfidence` is above 0.5; show generic onboarding below it. `matchGuaranteed` is `true` only for a deterministic match; use it to pick the destination, not as a credential, since a probabilistic match comes from a hashed match key built from the IP address and language, with time zone when available. Use it to route the user, not to identify them. Authenticate the user and check authorization separately before anything sensitive. The confidence bands are server-side, and the match window is configured per link in the dashboard (6 hours by default, 24 at most). There is no client-side match-window setting.

## Code Example

```swift
func handleLink(_ result: Result<WarpLinkDeepLink?, WarpLinkError>) {
    switch result {
    case .success(let deepLink?):
        let confidence = deepLink.matchConfidence ?? 0

        // A guaranteed match is a reliable hint, never an identity.
        if deepLink.matchGuaranteed {
            personalizeOnboarding(from: deepLink)
        }

        if confidence > 0.5 {
            navigate(to: deepLink.deepLinkUrl ?? deepLink.destination)
        } else {
            showWelcome(suggested: deepLink.destination)
        }
    case .success(nil):
        showOnboarding()                // deferred check ran, no match
    case .failure(let error):
        // Offline on first launch, say. The SDK will retry next launch.
        print("Deferred deep link error: \(error.localizedDescription)")
        showOnboarding()
    }
}
```

## Edge Cases

### Offline First Launch

If the device has no connectivity on first launch, the attempt fails with `.networkError` and is **not** marked complete. The SDK retries the attribution check on the next launch. You don't need to build your own retry loop, though you may still choose to show a default experience meanwhile.

### App Reinstall

Deleting the app clears the completed marker along with the app container, so the next launch runs the deferred check again and can match a fresh click. The request carries `is_reinstall: true`, because the device-level marker in the Keychain outlived the delete. Restoring a backup behaves the same way: the marker is excluded from backups, so a restored device attributes its install rather than skipping it.

### Multiple Links Clicked Before Install

A match key is a network rather than a device, so several clicks can land under one key: your own user clicking twice, or two strangers behind the same NAT. The platform keeps them as a list, newest first, up to 10 per match key. A second click no longer overwrites the first, so the install that belongs to the earlier click can still find it.

The server matches against the newest entry your app is allowed to claim, and removes only that entry once it becomes an install. When more than one entry was claimable, the match is scored lower to reflect that the answer was picked from a set.

## Related Guides

- [Attribution](attribution.md): the signal set and matching tiers
- [Error Handling](error-handling.md): handling deferred deep link errors
- [Troubleshooting](troubleshooting.md): common deferred deep link issues
