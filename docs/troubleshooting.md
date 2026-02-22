# Troubleshooting

Common issues and solutions when integrating the WarpLink iOS SDK.

## 1. Universal Links Don't Open My App

**Symptoms:** Tapping a WarpLink URL opens Safari instead of your app, or shows a web page.

**Possible Causes and Solutions:**

### Associated Domains entitlement missing

Verify that `applinks:aplnk.to` is added in your Xcode target under **Signing & Capabilities > Associated Domains**.

### AASA not configured in dashboard

Your iOS app must be registered in the WarpLink dashboard (**Settings > Apps**) with the correct bundle ID and team ID. WarpLink generates the AASA file automatically when you register the app.

### Testing on simulator

**Universal Links do not work on the iOS Simulator.** You must test on a physical iOS device.

### Link not registered

Ensure the link exists and is active in the WarpLink dashboard. Expired or disabled links will not open the app.

### Domain mismatch

The SDK only recognizes `aplnk.to` as a WarpLink domain. If you're testing with a different domain, the SDK will return `.invalidURL`.

### Apple Developer portal

Verify that the **Associated Domains** capability is enabled for your App ID in the [Apple Developer portal](https://developer.apple.com). Regenerate your provisioning profile after enabling it.

### Verify AASA is served correctly

```bash
curl -s https://aplnk.to/.well-known/apple-app-site-association | python3 -m json.tool
```

Look for your app's bundle ID and team ID in the `applinks.details` array. If they're missing, check your app registration in the WarpLink dashboard.

---

## 2. Deferred Deep Link Callback Never Fires

**Symptoms:** `checkDeferredDeepLink` never calls its completion handler, or always returns `nil`.

**Possible Causes and Solutions:**

### SDK not configured

`checkDeferredDeepLink` returns `.failure(.notConfigured)` if called before `WarpLink.configure()`. Ensure `configure()` runs before the deferred deep link check.

### First launch already consumed

The SDK uses UserDefaults to track first launch. If the first launch check has already been consumed (either by a previous call or because UserDefaults persisted across a reinstall), the SDK returns the cached result.

To test deferred deep links:
1. Delete the app from the device
2. Reset UserDefaults (or use a fresh device/simulator profile)
3. Click a WarpLink URL in Safari
4. Install the app via Xcode
5. Launch and check

### Network error

If there's no network connectivity on first launch, the attribution request fails. Enable `debugLogging` to see the error in the console.

### Check debug logging

```swift
WarpLink.configure(
    apiKey: "wl_live_your_api_key_here_abcdefgh",
    options: WarpLinkOptions(debugLogging: true)
)
```

Look for `[WarpLink]` messages in the Xcode console:
- `"First launch — collecting device signals for attribution"` — attribution check started
- `"Not first launch, returning cached attribution"` — not first launch
- `"Deferred deep link matched: <linkId>"` — match found
- `"No deferred deep link match"` — no match found
- `"Attribution match failed: ..."` — network or server error

---

## 3. API Key Validation Fails

**Symptoms:** Debug log shows `"API key validation failed"` or `"Invalid API key format"`.

**Possible Causes and Solutions:**

### Wrong format

API keys must start with `wl_live_` (production) or `wl_test_` (test), followed by exactly 32 alphanumeric characters. Example: `wl_live_abcdefghijklmnopqrstuvwxyz012345`.

If the format is wrong, `configure()` silently returns without configuring the SDK. Enable `debugLogging` to see the warning.

### Key revoked

Check the [WarpLink dashboard](https://warplink.app) under **Settings > API Keys** to verify your key is active. Generate a new key if needed.

### Network issue

Server-side validation requires network connectivity. The SDK caches a successful validation for 24 hours, so this only affects the first launch or after the cache expires.

---

## 4. Low Confidence Attribution Matches

**Symptoms:** `matchConfidence` is consistently low (below 0.5) on deferred deep links.

**Possible Causes and Solutions:**

### Match window too long

A longer match window means more time for IP addresses and network conditions to change. Try reducing it:

```swift
WarpLink.configure(
    apiKey: "wl_live_your_api_key_here_abcdefgh",
    options: WarpLinkOptions(matchWindowHours: 24)
)
```

### Shared IP / VPN

Users on shared networks (corporate VPNs, university Wi-Fi, carrier-grade NAT) may produce lower-quality fingerprints. This is inherent to probabilistic matching.

### JavaScript interstitial blocked

If the user's browser blocks JavaScript on the redirect page, the click-side signals are limited to IP and User-Agent. This reduces fingerprint quality and match confidence.

---

## 5. `handleDeepLink` Returns `.invalidURL`

**Symptoms:** `handleDeepLink` fails with `.invalidURL` for URLs you expect to be WarpLink URLs.

**Possible Causes and Solutions:**

### URL is not an `aplnk.to` domain

The SDK currently only recognizes `aplnk.to` as a WarpLink domain. URLs with other hosts (including custom domains) will return `.invalidURL`.

**Workaround:** Check the URL host before calling `handleDeepLink`:

```swift
.onOpenURL { url in
    guard url.host == "aplnk.to" else {
        // Handle non-WarpLink URLs separately
        return
    }
    WarpLink.handleDeepLink(url) { result in
        // ...
    }
}
```

Custom domain support in the SDK is planned for a future release.

---

## 6. Verifying AASA Configuration

The Apple App Site Association (AASA) file tells iOS which apps can handle Universal Links for a domain.

### Check AASA content

```bash
curl -s https://aplnk.to/.well-known/apple-app-site-association | python3 -m json.tool
```

### Expected structure

```json
{
    "applinks": {
        "apps": [],
        "details": [
            {
                "appID": "<TEAM_ID>.<BUNDLE_ID>",
                "paths": ["*"]
            }
        ]
    }
}
```

### What to check

1. Your `<TEAM_ID>.<BUNDLE_ID>` appears in the `details` array
2. The `paths` include the patterns that match your links
3. The response has the correct `Content-Type: application/json` header

### If your app is missing

Register your iOS app in the WarpLink dashboard (**Settings > Apps**) with the correct bundle ID and team ID. The AASA file is regenerated automatically.

---

## 7. Debug Logging

Enable debug logging to trace SDK behavior:

```swift
WarpLink.configure(
    apiKey: "wl_live_your_api_key_here_abcdefgh",
    options: WarpLinkOptions(debugLogging: true)
)
```

### What to look for

All SDK log messages are prefixed with `[WarpLink]` in the Xcode console.

**Configuration:**
- `"Configured with API key: wl_live_****xxxx"` — SDK initialized (key is masked)
- `"API endpoint: https://api.warplink.app/v1"` — endpoint in use
- `"Match window: 72 hours"` — deferred deep link match window

**API key validation:**
- `"Validating API key..."` — server validation started
- `"API key validated successfully"` — key is valid
- `"API key validation cached, skipping"` — using cached validation (24hr)

**Universal Links:**
- `"Resolving Universal Link: https://aplnk.to/abc123"` — link resolution started
- `"Resolved link: abc123 → https://..."` — link resolved successfully

**Deferred deep links:**
- `"First launch — collecting device signals for attribution"` — first launch detected
- `"Deferred deep link matched: <linkId>"` — attribution match found
- `"No deferred deep link match"` — no match
- `"Not first launch, returning cached attribution"` — returning cached result

---

## 8. Xcode Entitlements Setup

If Universal Links aren't working, double-check your Xcode entitlements configuration:

1. Select your app target in Xcode
2. Go to **Signing & Capabilities** tab
3. Ensure **Associated Domains** is listed as a capability
4. The `applinks:aplnk.to` entry should be present
5. Verify **Automatically manage signing** is enabled, or manually update your provisioning profile

### Provisioning Profile

If you manage provisioning profiles manually:

1. Go to [developer.apple.com](https://developer.apple.com) > **Certificates, Identifiers & Profiles**
2. Select your App ID > enable **Associated Domains**
3. Regenerate your provisioning profile
4. Download and install the new profile in Xcode

## Related Guides

- [Integration Guide](integration-guide.md) — step-by-step setup
- [Error Handling](error-handling.md) — handling SDK errors programmatically
- [Deferred Deep Links](deferred-deep-links.md) — understanding deferred attribution
