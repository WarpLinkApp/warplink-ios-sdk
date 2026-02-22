# Architecture Overview

How the WarpLink iOS SDK communicates with the WarpLink platform. This overview is aimed at SDK consumers — it explains the flows you need to understand, not internal infrastructure details.

## Link Creation

Developers create links via the [WarpLink dashboard](https://warplink.app) or the [REST API](https://api.warplink.app/v1). Each link has:

- A **short URL** (e.g., `https://aplnk.to/abc123`)
- A **destination URL** — where the user should end up
- An optional **iOS deep link URL** (e.g., `myapp://product/123`)
- Optional **custom parameters** — arbitrary key-value data attached to the link

When a link is created, it's stored in the database and cached at the edge for sub-10ms resolution globally.

## Click Flow

When a user clicks a WarpLink URL:

```
User taps link
    → Edge server resolves the link (sub-10ms)
    → Parses User-Agent
    → Bot? → Returns HTML with OG/Twitter Card tags (social previews)
    → Real user on iOS with app installed?
        → 302 redirect → iOS Universal Link opens your app
    → Real user on iOS without app?
        → Captures browser signals (JS interstitial)
        → Redirects to App Store (or fallback URL)
    → Other platform?
        → 302 redirect to destination URL
```

The key insight: the edge server decides where to send the user based on their device, whether the app is installed, and the link's configuration.

## Universal Link Resolution

When iOS opens your app via a Universal Link:

```
iOS opens your app with the URL
    → Your app calls WarpLink.handleDeepLink(url)
    → SDK validates the URL is a WarpLink domain (aplnk.to)
    → SDK extracts the slug from the URL path
    → SDK calls GET /links/resolve/{slug}?domain=aplnk.to
    → API returns link data (destination, iOS URL, custom params)
    → SDK returns WarpLinkDeepLink to your completion handler
    → Your app routes the user to the intended content
```

The API call resolves the short link slug to its full link data, including the destination URL, any iOS-specific deep link URL, and custom parameters.

## Deferred Deep Link Flow

When a user clicks a link before the app is installed:

```
User taps link (app not installed)
    → Edge captures browser signals (IP, UA, language, screen, timezone)
    → Stores signals as a deferred payload (keyed by fingerprint)
    → Redirects user to App Store

User installs and opens the app
    → SDK detects first launch (UserDefaults)
    → SDK collects device signals (screen, timezone, language, IDFV)
    → SDK calls POST /attribution/match with device signals
    → Server compares device signals against stored click signals
    → If IDFV matches → deterministic match (confidence 1.0)
    → If fingerprint matches → probabilistic match (confidence 0.4–0.85)
    → SDK returns WarpLinkDeepLink with isDeferred: true
    → SDK caches the result for subsequent launches
    → Your app routes the user to the intended content
```

## SDK Internals

### Initialization

When you call `WarpLink.configure(apiKey:options:)`:

1. **Format validation** — checks the API key matches `wl_live_` or `wl_test_` + 32 alphanumeric characters
2. **Component setup** — creates internal API client, storage, fingerprint collector, and logger
3. **Server validation** — async call to `/sdk/validate` to verify the key is active
4. **Validation caching** — successful validation is cached for 24 hours (stored in UserDefaults) to avoid redundant network calls

### First Launch Detection

The SDK uses UserDefaults to track whether the app has been launched before. On the very first launch, `checkDeferredDeepLink` performs the attribution request. On all subsequent launches, it returns the cached result.

**Note:** UserDefaults may persist across app reinstalls depending on iOS version and backup settings. See [Deferred Deep Links](deferred-deep-links.md) for edge cases.

### Fingerprint Collection

On first launch, the SDK collects:

| Signal | Source |
|--------|--------|
| Screen resolution | `UIScreen.main.bounds` |
| Timezone offset | `TimeZone.current.secondsFromGMT()` |
| Preferred languages | `Locale.preferredLanguages` |
| IDFV | `UIDevice.current.identifierForVendor` |

These raw signals are sent to the server, which computes the fingerprint using the client IP + these signals. The SDK does **not** hash or compute fingerprints locally.

### Attribution Caching

After the first deferred deep link check, the result (whether a match was found or not) is cached in UserDefaults. This means:

- The attribution API is called at most once per app install
- Subsequent calls to `checkDeferredDeepLink` return instantly from cache
- No unnecessary network requests on app launches after the first

## Related Guides

- [Deferred Deep Links](deferred-deep-links.md) — detailed deferred deep link flow
- [Attribution](attribution.md) — matching tiers and confidence scores
- [API Reference](api-reference.md) — all public types and methods
