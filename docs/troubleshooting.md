# Troubleshooting

Common issues and solutions when integrating the WarpLink iOS SDK.

## 1. Universal Links Don't Open My App

**Symptoms:** Tapping a WarpLink URL opens Safari instead of your app, or shows a web page.

**Possible Causes and Solutions:**

### Associated Domains entitlement missing

Verify that `applinks:aplnk.to` is added in your Xcode target under **Signing & Capabilities > Associated Domains**.

### AASA not configured in dashboard

Your iOS app must be registered in the WarpLink dashboard (**Apps**) with the correct bundle ID and team ID. WarpLink generates the AASA file automatically when you register the app.

### Testing on simulator

**Universal Links do not work on the iOS Simulator.** You must test on a physical iOS device.

### Link not registered

Ensure the link exists and is active in the WarpLink dashboard. Expired or disabled links will not open the app.

### Domain mismatch

The SDK recognizes `aplnk.to`, any domain you declare locally (`WarpLinkOptions.linkDomains` or the `WarpLinkDomains` Info.plist array), and your org's verified custom domains fetched from `/sdk/validate` on `configure()`. A URL on a host that isn't in that set returns `.invalidURL`. If you're testing a custom domain, declare it locally and confirm it is verified and live in the dashboard.

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

### An API key was used instead of an SDK key

Install attribution requires an **SDK key**. An API key cannot record installs, whatever scopes it holds, so the attribution request is rejected with `403` and surfaces as `.invalidApiKey`. Telltale symptom: deep links resolve normally, `isApiKeyValid` is `true`, but no installs appear in your dashboard.

Create one in the dashboard under **API Keys** > **SDK key**, then pass it to `WarpLink.configure()`.

### SDK not configured

`checkDeferredDeepLink` returns `.failure(.notConfigured)` if called before `WarpLink.configure()`. Ensure `configure()` runs before the deferred deep link check.

### First launch already completed

The SDK marks attribution **completed** only on a definitive server response, and that marker is scoped to one install. Within an install, every later launch returns the cached result instead of re-attributing. A failed attempt (for example, offline) is not marked complete, so the SDK retries on the next launch.

Deleting the app clears the marker, so a reinstall runs the check again. It is reported with `is_reinstall: true`, since a separate Keychain marker remembers that the device was attributed before. That marker never blocks a check.

To re-test deferred deep links:
1. Delete the app from the device
2. Click a WarpLink URL in Safari
3. Install the app via Xcode
4. Launch and check

### Network error

If there's no network connectivity on first launch, the attribution request fails. Enable `debugLogging` to see the error in the console.

### Check debug logging

```swift
WarpLink.configure(
    apiKey: "wl_live_yoursdkkeyhere000000000000000000",
    options: WarpLinkOptions(debugLogging: true)
)
```

Look for `[WarpLink]` messages in the Xcode console:
- `"First launch: collecting device signals for attribution"`: attribution check started
- `"Retrying deferred attribution (prior attempt did not complete)"`: retry after a failed attempt
- `"Attribution already complete for this install, returning cached result"`: attribution already done
- `"Deferred deep link matched: <linkId>"`: match found
- `"No deferred deep link match"`: no match found
- `"Attribution match failed (will retry next launch): ..."`: network or server error

---

## 3. SDK Key Validation Fails

**Symptoms:** Debug log shows `"WARNING: API key rejected by server (invalid or revoked)."` or `"WARNING: Invalid API key format: wl_live_****xxxx"`.

**Possible Causes and Solutions:**

### Wrong format

SDK keys start with `wl_live_` followed by exactly 32 alphanumeric characters. Example: `wl_live_yoursdkkeyhere000000000000000000`.

If the format is wrong, `configure()` dispatches `WarpLinkError.invalidApiKeyFormat` to your `onLink` sink and always logs a `[WarpLink] WARNING:` line (even without `debugLogging`). The SDK stays unconfigured.

### Key revoked

Check the [WarpLink dashboard](https://warplink.app) under **API Keys** to verify your key is active. Generate a new SDK key if needed.

### Network issue

Server-side validation requires network connectivity. The SDK caches a successful validation for 24 hours, so this only affects the first launch or after the cache expires.

---

## 4. Low Confidence Attribution Matches

**Symptoms:** `matchConfidence` is consistently low (below 0.5) on deferred deep links.

**Possible Causes and Solutions:**

### Match window too long

A longer match window means more time for IP addresses and network conditions to change, which lowers probabilistic confidence. The match window is server-side, set per link in the dashboard (there is no client-side setting). Shorten it there if you want tighter, higher-confidence matches.

### Shared IP / VPN

Users on shared networks (corporate VPNs, university Wi-Fi, carrier-grade NAT) may produce lower-quality fingerprints. This is inherent to probabilistic matching.

### Time zone or language changes

The enriched fingerprint uses the device's preferred language and timezone offset. A user who changes either between click and install (or crosses a timezone) may match with lower confidence.

---

## 5. `handleDeepLink` Returns `.invalidURL`

**Symptoms:** `handleDeepLink` fails with `.invalidURL` for URLs you expect to be WarpLink URLs.

**Possible Causes and Solutions:**

### URL host is not one of your WarpLink domains

The SDK recognizes `aplnk.to`, the domains you declare locally, and your org's **verified custom domains** fetched from `/sdk/validate` on `configure()`. A URL whose host isn't in that set returns `.invalidURL` (and `open(_:)` returns `false`).

If a custom-domain link isn't recognized:
- **Declare the domain locally.** The server's list arrives over the network, so on a first launch, or on a launch with no connectivity, it is not there yet. Pass `WarpLinkOptions(linkDomains: ["links.yourbrand.com"])`, or add a `WarpLinkDomains` array of strings to your Info.plist. A declared domain works from the moment `configure()` returns.
- Confirm the domain is **verified and live** in the dashboard (unverified domains aren't returned by the server, though a declared one still works).
- Check the spelling. Entries are trimmed and lowercased, and a full URL is reduced to its host, but `www.` is significant: `www.yourbrand.com` and `yourbrand.com` are different hosts.
- Make sure the domain is also listed in your **Associated Domains** entitlement (`applinks:go.yourbrand.com`), or iOS won't open your app for it in the first place.

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

Register your iOS app in the WarpLink dashboard (**Apps**) with the correct bundle ID and team ID. The AASA file is regenerated automatically.

---

## 7. Debug Logging

Enable debug logging to trace SDK behavior:

```swift
WarpLink.configure(
    apiKey: "wl_live_yoursdkkeyhere000000000000000000",
    options: WarpLinkOptions(debugLogging: true)
)
```

### What to look for

All SDK log messages are prefixed with `[WarpLink]` in the Xcode console.

**Configuration:**
- `"Configured with API key: wl_live_****xxxx"`: SDK initialized (key is masked)
- `"API endpoint: https://api.warplink.app/v1"`: endpoint in use

**API key validation:**
- `"Validating API key..."`: server validation started
- `"API key validated successfully"`: key is valid
- `"API key validation cached, skipping"`: using cached validation (24hr)
- `"WARNING: API key rejected by server (invalid or revoked)..."`: printed even without debug logging; `WarpLink.isApiKeyValid` is `false`

**Universal Links:**
- `"Resolving Universal Link: https://aplnk.to/abc123"`: link resolution started
- `"Resolved link: abc123"`: link resolved successfully

**Deferred deep links:**
- `"First launch: collecting device signals for attribution"`: first launch detected
- `"Retrying deferred attribution (prior attempt did not complete)"`: retry after a failed attempt
- `"Deferred deep link matched: <linkId>"`: attribution match found
- `"No deferred deep link match"`: no match
- `"Attribution already complete for this install, returning cached result"`: returning cached result

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

- [Integration Guide](integration-guide.md): step-by-step setup
- [Error Handling](error-handling.md): handling SDK errors programmatically
- [Deferred Deep Links](deferred-deep-links.md): understanding deferred attribution
