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
    → Your app hands the URL to the SDK (WarpLink.open / .continue, or handleDeepLink)
    → SDK validates the host is a known WarpLink domain (aplnk.to + your declared and verified domains)
    → SDK extracts the slug from the URL path
    → SDK calls GET /links/resolve/{slug}?domain={host}
    → API returns link data (destination, iOS URL, custom params)
    → SDK delivers a WarpLinkDeepLink to onLink (or your completion handler)
    → Your app routes the user to the intended content
```

The known-domain set is the union of four sources: `aplnk.to`, `WarpLinkOptions.linkDomains`, the `WarpLinkDomains` Info.plist array, and the verified custom domains returned by `/sdk/validate` (cached for the next launch). The first three are available synchronously at `configure()`, which is what a link arriving on a first launch needs: `open(_:)` has to answer before the server can.

The API call resolves the short link slug to its full link data, including the destination URL, any iOS-specific deep link URL, and custom parameters.

## Deferred Deep Link Flow

When a user clicks a link before the app is installed:

```
User taps link (app not installed)
    → Edge records the click's fingerprint (IP + language + timezone) and link
    → Stores it as a deferred payload (keyed by fingerprint)
    → Redirects user to App Store

User installs and opens the app
    → configure() runs the deferred check (autoDeferredCheck, on by default)
    → SDK collects device signals (preferred language, timezone offset, IDFV)
    → SDK calls POST /attribution/match with those raw signals
    → Server derives the IP, computes the fingerprint, compares to stored clicks
    → If IDFV matches → deterministic match (confidence 1.0)
    → If fingerprint matches → probabilistic match (confidence varies by window)
    → SDK delivers a WarpLinkDeepLink with isDeferred: true to onLink
    → SDK marks attribution complete and caches the result
    → Your app routes the user to the intended content
```

## SDK Internals

### Initialization

When you call `WarpLink.configure(apiKey:options:)`:

1. **Format validation**: checks the SDK key matches `wl_live_` or `wl_test_` + 32 alphanumeric characters
2. **Component setup** — creates internal API client, storage, fingerprint collector, and logger
3. **Server validation** — async call to `/sdk/validate` to verify the key is active
4. **Validation caching** — successful validation is cached for 24 hours (stored in UserDefaults) to avoid redundant network calls

### First Launch Detection (attempt vs complete)

The SDK splits first-launch tracking into two states:

- **completed** — a definitive server response (match or no-match) was received. Stored in a backup-excluded file inside the app container, so it is scoped to one install: it never comes back from a delete or from a restored backup, and a reinstall is attributed again. Once complete, `checkDeferredDeepLink` returns the cached result with no network call for the rest of that install.
- **attempted**: an attempt has started this install. Stored in the same backup-excluded file as the completion marker, so a restore does not carry it. If an attempt fails (e.g. offline) it is marked attempted but **not** completed, so the SDK retries on the next launch.

A third marker, in the **Keychain**, records that this device has been attributed at least once. It outlives both a delete and a restore, and it gates nothing. Its only job is to set `is_reinstall` on the attribution request so a reinstall can be told apart from a first install later.

See [Deferred Deep Links](deferred-deep-links.md) for edge cases.

### Signal Collection

On the attribution attempt, the SDK sends:

| Signal | Source |
|--------|--------|
| Preferred language | `Locale.preferredLanguages.first` (raw) |
| Timezone name | `TimeZone.current.identifier` (IANA, e.g. `America/Toronto`) |
| Timezone offset | `-(TimeZone.current.secondsFromGMT() / 60)` (minutes, JS convention) |
| IDFV | `UIDevice.current.identifierForVendor` |
| Reinstall flag | `is_reinstall`: whether this device completed attribution under an earlier install |

It also identifies the caller: `platform`, `sdk_version`, and the app's bundle identifier (`app_bundle_id`), so the server can tell which app of an organization the install belongs to.

These raw signals are sent to the server, which derives the client IP and computes the fingerprint. The SDK does **not** hash or compute fingerprints locally, and does **not** send User-Agent or screen dimensions (removed in 1.1.0; they never matched across the browser/native boundary).

### Attribution Caching

Once attribution completes, the result (match or no-match) is cached. This means:

- The attribution API is called at most once per app install. A reinstall or a backup restore is a new install and is attributed again, except in the rare case where the completion marker could not be written to the backup-excluded file and fell back to UserDefaults.
- Subsequent calls to `checkDeferredDeepLink` return instantly from cache
- A failed attempt is not cached and does not block a retry on the next launch

## Related Guides

- [Deferred Deep Links](deferred-deep-links.md) — detailed deferred deep link flow
- [Attribution](attribution.md) — matching tiers and confidence scores
- [API Reference](api-reference.md) — all public types and methods
