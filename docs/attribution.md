# Install Attribution

WarpLink uses two tiers of attribution matching to connect app installs and opens to the links that drove them. The SDK collects device signals and sends them to the WarpLink API, which determines the match.

## Overview

When a user interacts with a WarpLink URL, the platform captures signals from the click. When the app opens (or is installed and opened for the first time), the SDK collects device-side signals. The server compares both sets of signals to determine if there's a match.

The result is returned as a `WarpLinkDeepLink` with `matchType` and `matchConfidence` properties.

## Deterministic Matching (IDFV)

**Used for:** Re-engagement — when the app is already installed or was previously installed on the same device.

| Property | Value |
|----------|-------|
| Signal | IDFV (`UIDevice.current.identifierForVendor`) |
| Match type | `.deterministic` |
| Confidence | 1.0 (exact match) |
| Requires ATT? | No |
| Requires user permission? | No |

IDFV (Identifier for Vendor) is a UUID unique to the combination of your app and the device. It's the same across all apps from the same vendor on a single device. It does not require any user permission and is **exempt from App Tracking Transparency (ATT)**.

The SDK reads IDFV via `UIDevice.current.identifierForVendor` and includes it in attribution requests. If the server finds a matching IDFV in stored click data, it returns a deterministic match with confidence 1.0.

## Probabilistic Matching (Enriched Fingerprint)

**Used for:** First-install attribution — when the app was not previously installed.

| Property | Value |
|----------|-------|
| Signals | IP address + User-Agent + Accept-Language + screen resolution + timezone |
| Match type | `.probabilistic` |
| Confidence | 0.40 to 0.85 (varies by time window) |
| Requires ATT? | No |
| Requires user permission? | No |

When a user clicks a WarpLink URL, a brief JavaScript interstitial captures browser-side signals (IP, User-Agent, Accept-Language, screen size, timezone). On first app launch, the SDK collects the same categories of signals from the device and sends them to the attribution API. The server computes a fingerprint from both sets and checks for a match.

### Confidence by Time Window

| Time Since Click | Confidence |
|------------------|------------|
| < 1 hour | 0.85 |
| < 24 hours | 0.65 |
| < 72 hours | 0.40 |
| Multiple candidates | -0.15 per additional match |

Confidence decreases over time because IP addresses and network conditions change. The multiple-candidate penalty applies when more than one stored click matches the fingerprint.

## Interpreting Match Results

The `WarpLinkDeepLink` returned by `handleDeepLink` and `checkDeferredDeepLink` includes:

- `matchType: MatchType?` — `.deterministic` or `.probabilistic`
- `matchConfidence: Double?` — 0.0 to 1.0

### Recommended Thresholds

| Confidence | Recommended Action |
|------------|-------------------|
| 1.0 (deterministic) | Route directly to content |
| > 0.5 (probabilistic) | Route to content — high confidence |
| 0.3 to 0.5 | Show content with a confirmation (e.g., "Were you looking for...?") |
| < 0.3 | Show generic onboarding — too uncertain |

```swift
WarpLink.checkDeferredDeepLink { result in
    if case .success(let deepLink) = result, let deepLink = deepLink {
        let confidence = deepLink.matchConfidence ?? 0

        switch confidence {
        case 0.5...:
            navigateTo(deepLink.destination)
        case 0.3..<0.5:
            showSuggestion(deepLink.destination)
        default:
            showOnboarding()
        }
    }
}
```

## App Tracking Transparency (ATT)

The WarpLink SDK:

- **Does NOT use IDFA** (Advertising Identifier)
- **Does NOT prompt for ATT permission**
- **Uses only IDFV**, which is [exempt from ATT](https://developer.apple.com/documentation/apptrackingtransparency) — it does not track users across apps
- **Does NOT interfere** with your app's own ATT strategy

You can use WarpLink alongside any ATT implementation. The SDK's attribution works independently of the user's ATT consent choice.

## Privacy Considerations

### Signals Collected by the SDK

| Signal | Purpose | Source |
|--------|---------|--------|
| Screen resolution | Fingerprint component | `UIScreen.main.bounds` |
| Timezone offset | Fingerprint component | `TimeZone.current.secondsFromGMT()` |
| Preferred languages | Fingerprint component | `Locale.preferredLanguages` |
| IDFV | Deterministic matching | `UIDevice.current.identifierForVendor` |

The SDK does **not** collect:
- IDFA (Advertising Identifier)
- Location data
- Contacts or personal data
- App usage data
- Cross-app identifiers

### Data Handling

- Device signals are sent to the WarpLink API over HTTPS
- Fingerprint data is used solely for attribution matching
- No cross-app tracking is performed
- IDFV is scoped to your vendor — WarpLink cannot use it to track users across different vendors' apps

## Related Guides

- [Deferred Deep Links](deferred-deep-links.md) — how deferred deep linking uses attribution
- [API Reference](api-reference.md) — `MatchType` and `WarpLinkDeepLink` documentation
