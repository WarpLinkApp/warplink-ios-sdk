# Install Attribution

WarpLink uses two tiers of attribution matching to connect app installs and opens to the links that drove them. The SDK collects a small set of raw device signals and sends them to the WarpLink API, which computes the fingerprint server-side (using the request IP) and determines the match.

## Overview

When a user interacts with a WarpLink URL, the platform captures signals from the click. When the app opens (or is installed and opened for the first time), the SDK sends raw device signals. The **server** computes a fingerprint from both sides and determines whether there's a match. The SDK never hashes anything locally and never sends a precomputed fingerprint or an IP address.

The result is returned as a `WarpLinkDeepLink` with `matchType`, `matchConfidence`, and `matchGuaranteed` properties.

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

The SDK reads IDFV via `UIDevice.current.identifierForVendor` and includes it as `device_id` in attribution requests. If the server finds a matching IDFV in stored click data, it returns a deterministic match with confidence 1.0 and `matchGuaranteed: true`.

## Probabilistic Matching (Enriched Fingerprint)

**Used for:** First-install attribution — when the app was not previously installed.

| Property | Value |
|----------|-------|
| SDK signals | Preferred language + timezone (server adds the request IP) |
| Match type | `.probabilistic` |
| Confidence | 0.20 to 0.85 before the multipliers below, never `matchGuaranteed` |
| Requires ATT? | No |
| Requires user permission? | No |

On first app launch, the SDK sends its raw signals plus the request context. The server hashes them together with the IP it derives from the request and compares against the fingerprint stored at click time.

The fingerprint is `HMAC(secret, ip + "|" + normalizedLanguage + "|" + ianaTimezone)`. If the SDK sent no zone name (SDKs that send no zone name), the server falls back to `timezoneMinutes` in that last position, then to language alone.

### The attribution signal set (v1.1.0)

| Signal | Field | Source | Notes |
|--------|-------|--------|-------|
| Preferred language | `accept_language` | `Locale.preferredLanguages.first` | Sent **raw** (e.g. `en-US`). The server normalizes to the primary subtag (`en`). Do not pre-normalize. |
| Timezone | `timezone` | `TimeZone.current.identifier` | The IANA zone name (e.g. `America/Toronto`). New in 1.1.0. |
| Timezone offset | `timezone_offset` | `-(TimeZone.current.secondsFromGMT() / 60)` | Minutes, JS `getTimezoneOffset()` convention (UTC+2 → -120), DST-aware. Still sent as the fallback key. |
| IDFV | `device_id` | `UIDevice.current.identifierForVendor` | Deterministic re-engagement match. |
| Bundle ID | `app_bundle_id` | `Bundle.main.bundleIdentifier` | Identifies which of your apps this install is. Not part of the fingerprint. |
| Reinstall flag | `is_reinstall` | SDK markers | `true` when this device completed attribution under an earlier install. Not part of the fingerprint. |
| IP address | (server-derived) | request | Never sent by the SDK. |

**On the zone name (new in 1.1.0).** The IANA zone name carries far more entropy than the offset it joins: roughly 340 zones against roughly 38 offsets. It also does not shift at a daylight-saving boundary, which used to break a click and its install apart when the clocks changed between them. Requests that carry it are scored as the `enriched_tz` variant.

**Removed in 1.1.0:** the SDK no longer collects or sends **User-Agent** or **screen width/height**. Those never matched across the browser/native-app boundary (a browser UA is not an app UA) or the CSS-pixels/points/physical-pixels boundary, so they only added noise. The body carries `accept_language`, `timezone`, and `timezone_offset` (plus `platform`, `fingerprint_version`, `sdk_version`, `app_bundle_id`, `is_reinstall`, and optional `device_id`).

**On `app_bundle_id`.** An API key is scoped to your organization, not to a single app, and every app signed by the same Apple team shares one IDFV. If your organization ships more than one app, the bundle ID is what lets the server attribute an install to the app it actually happened in. It is read from your app bundle automatically, so there is nothing to configure.

**On `is_reinstall`.** A reinstall counts as an install, so attribution runs again after one. The flag says whether this device had completed attribution before, under an install that is now gone. It comes from a Keychain marker that outlives an app delete and a backup restore, and that marker never blocks a check. Installs and reinstalls are reported as one number; the flag exists so they can be separated later. Nothing to configure.

### Confidence by Time Window

The elapsed time and the fingerprint variant set the ceiling. `enriched_tz` is the zone-name variant that an SDK collecting a zone name sends; `enriched` is the offset variant kept for older SDKs; `basic` is the language-only key the server tries last.

| Time Since Click | `enriched_tz` | `enriched` | `basic` |
|------------------|---------------|------------|---------|
| < 1 hour | 0.85 | 0.80 | 0.70 |
| < 3 hours | 0.65 | 0.60 | 0.50 |
| < 6 hours | 0.50 | 0.45 | 0.35 |
| < 24 hours | 0.30 | 0.25 | 0.20 |
| 24 hours or more | no match | no match | no match |

Those are ceilings. Two multipliers pull the score down when the answer was less certain than the clock alone suggests:

| Condition | Multiplier |
|-----------|------------|
| More than one claimable click sat in the fingerprint's bucket | 0.6 |
| The click's IP was carrier-grade NAT or private | 0.6 |
| The click's IP was a household IPv4 address | 0.9 |
| The click's IP was IPv6 | 1.0 |

### The match window

The match window is server-side, set per link in the dashboard. It **defaults to 6 hours and cannot exceed 24**; a link created before that ceiling may still carry a longer value, but the platform clamps it to 24 hours on read. There is no client-side match-window setting.

The window is short on purpose. The fingerprint key is a network, not a device: an IP address, a normalized language, and a timezone. Every phone behind one NAT that shares a language and timezone lands in the same bucket, so each extra hour lets another stranger join it while adding almost no real matches. This governs the probabilistic tier only. The deterministic path (IDFV) reads stored click data instead of the fingerprint bucket, so the window does not apply to it.

## Interpreting Match Results

The `WarpLinkDeepLink` returned to `onLink` (or by `handleDeepLink` / `checkDeferredDeepLink`) includes:

- `matchType: MatchType?` — `.deterministic` or `.probabilistic`
- `matchConfidence: Double?` — 0.0 to 1.0
- `matchGuaranteed: Bool`, `true` only for a deterministic match

### Gate sensitive work on `matchGuaranteed`

`matchGuaranteed` is `true` only when the match came from a deterministic signal, which on iOS is the IDFV. Gate anything sensitive on it (auto sign-in, restoring an account, showing personal data) rather than on a confidence threshold. A probabilistic match is a best guess drawn from a network-shaped fingerprint, so even a high score can name the wrong user.

```swift
if deepLink.matchGuaranteed {
    restoreAccount(from: deepLink)   // this is the person we think it is
} else {
    showContent(from: deepLink)      // route content, but never identity
}
```

### Recommended Thresholds

| Confidence | Recommended Action |
|------------|-------------------|
| 1.0 (deterministic) | Route directly to content |
| > 0.5 (probabilistic) | Route to content — high confidence |
| 0.3 to 0.5 | Show content with a confirmation (e.g., "Were you looking for...?") |
| < 0.3 | Show generic onboarding — too uncertain |

```swift
WarpLinkOptions(onLink: { result in
    guard case .success(let deepLink?) = result else { return }
    let confidence = deepLink.matchConfidence ?? 0

    switch confidence {
    case 0.5...:
        navigate(to: deepLink)
    case 0.3..<0.5:
        showSuggestion(deepLink)
    default:
        showOnboarding()
    }
})
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
| Preferred language | Fingerprint component | `Locale.preferredLanguages.first` |
| Timezone name | Fingerprint component | `TimeZone.current.identifier` |
| Timezone offset | Fingerprint component (fallback key) | `TimeZone.current.secondsFromGMT()` |
| IDFV | Deterministic matching | `UIDevice.current.identifierForVendor` |
| Reinstall flag (`is_reinstall`) | Routing a returning user back to the content they tapped, and separating reinstalls from first installs afterwards | Keychain install marker |

The SDK does **not** collect:
- IDFA (Advertising Identifier)
- User-Agent or screen dimensions
- Location data
- Contacts or personal data
- App usage data: no screens, sessions, taps, or in-app events. The reinstall flag above is install history, not usage.
- Cross-app identifiers

### Data Handling

- Device signals are sent to the WarpLink API over HTTPS
- The fingerprint is computed server-side and used solely for attribution matching
- No cross-app tracking is performed
- IDFV is scoped to your vendor, so WarpLink cannot use it to track users across different vendors' apps
- The reinstall flag is retained on the install record, so it outlives the request that carried it

### Privacy manifest

The SDK ships `PrivacyInfo.xcprivacy` as a target resource, so Xcode folds it
into your app's privacy report automatically. It declares:

- `NSPrivacyAccessedAPICategoryUserDefaults`, reason `CA92.1`, for the SDK state
  kept in your app's own `UserDefaults`. Without this declaration an app that
  embeds the SDK can be rejected at upload with ITMS-91053.
- `NSPrivacyAccessedAPICategorySystemBootTime`, reason `35F9.1`, for the
  `ProcessInfo.systemUptime` reading behind the deep-link dedupe window. It
  measures elapsed time between two dispatches inside one run. The value is
  never persisted and never leaves the device, which is what `35F9.1` requires.
- `NSPrivacyCollectedDataTypeDeviceID` for the IDFV.
- `NSPrivacyCollectedDataTypeOtherDataTypes` for the reinstall flag.

Both collected types are declared as not linked to identity and not used for
tracking, with purpose App Functionality. `NSPrivacyTracking` is `false` and
`NSPrivacyTrackingDomains` is empty.

Your own App Privacy answers in App Store Connect still cover your whole app.
The manifest tells Apple what this SDK contributes; it does not fill your form in
for you.

## Related Guides

- [Deferred Deep Links](deferred-deep-links.md) — how deferred deep linking uses attribution
- [API Reference](api-reference.md) — `MatchType` and `WarpLinkDeepLink` documentation
