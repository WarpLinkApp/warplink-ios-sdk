# Error Handling

The WarpLink SDK uses the `WarpLinkError` enum for all error cases. Every error conforms to `LocalizedError` and provides a human-readable `errorDescription`.

## Error Cases

### `.notConfigured`

**When:** Any SDK method is called before `WarpLink.configure(apiKey:options:)`.

**Fix:** Call `configure()` during app initialization, in your SwiftUI `App.init()` or UIKit `application(_:didFinishLaunchingWithOptions:)`.

```swift
// Ensure this runs before any handleDeepLink or checkDeferredDeepLink calls
WarpLink.configure(apiKey: "wl_live_yoursdkkeyhere000000000000000000")
```

---

### `.invalidApiKeyFormat`

**When:** The SDK key passed to `configure()` does not match the expected format: `wl_live_` or `wl_test_` followed by exactly 32 alphanumeric characters.

**Fix:** Verify your SDK key in the [WarpLink dashboard](https://warplink.app) under **API Keys**. Ensure you're copying the full key.

**Note:** This error surfaces through the `onLink` sink: `configure()` dispatches `WarpLinkError.invalidApiKeyFormat` to `onLink` and always logs a `[WarpLink] WARNING:` line (even without `debugLogging`), then stays unconfigured.

---

### `.invalidApiKey`

**When:** The server rejects the key (HTTP 401 or 403). The key may be revoked, expired, incorrect, or an API key rather than an SDK key.

**Fix:**
1. Confirm you are using an **SDK key**, not an API key. Only an SDK key can record install attribution, so an API key with `links:read` still passes `/sdk/validate` and resolves links while every attribution call comes back `403`
2. Check that the key in your build matches the one shown in the dashboard. A stale or partially copied key can still pass local format validation and then be rejected by the server
3. Verify the key is still active in the dashboard under **API Keys**
4. Generate a new key if the current one was revoked

---

### `.networkError(Error)`

**When:** A network request fails: no internet connectivity, DNS resolution failure, or request timeout.

**Fix:** Check device connectivity and show an offline state. A retry loop of your own is not the first thing to reach for here, because the SDK has already run one.

Before you see this, the SDK has already tried again. A resolve or a deferred check that fails on a dead or flaky connection, or with a 5xx, is attempted up to three times, with short waits between attempts. Every attempt has its own time limit, so one that hangs rather than fails cannot swallow the others, and the whole sequence is limited to about twelve seconds. A weak connection usually delivers on the second attempt, in about eight. By the time `.networkError` reaches you, all of those attempts have failed. Refusals are never retried: a 404, a 403 and an expired link are answered on the first attempt, because the server will give the same answer to the second.

A failed resolve also releases the SDK's duplicate-tap guard, so a user who taps the same link again straight away really re-resolves it rather than being handed the failure back.

```swift
case .failure(let error):
    if case .networkError(let underlyingError) = error {
        let nsError = underlyingError as NSError
        if nsError.domain == NSURLErrorDomain {
            // Handle specific URL errors
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                // Show offline message, retry when connected
                break
            case NSURLErrorTimedOut:
                // Retry after delay
                break
            default:
                break
            }
        }
    }
```

---

### `.serverError(statusCode: Int, message: String)`

**When:** The WarpLink API returns a non-2xx HTTP status code.

**Fix:** Check the `statusCode` to determine the appropriate response:

| Status Code | Meaning | Action |
|-------------|---------|--------|
| 401 | Unauthorized | Check the key you passed to `configure()` |
| 403 | Forbidden | A password protected link returns `.passwordRequired`, otherwise confirm it is an SDK key, not an API key |
| 429 | Rate limited | Retry after delay |
| 500 | Server error | Retry later, report if persistent |
| 503 | Service unavailable | Retry later |

```swift
case .failure(let error):
    if case .serverError(let statusCode, let message) = error {
        if statusCode == 429 {
            // Rate limited. Retry after a delay.
        } else if statusCode >= 500 {
            // Server issue: retry later
        }
    }
```

---

### `.invalidURL`

**When:** A URL passed to `handleDeepLink(_:completion:)` is not a recognized WarpLink Universal Link. The SDK recognizes `aplnk.to`, the domains you declare via `WarpLinkOptions.linkDomains` or the `WarpLinkDomains` Info.plist array, and your org's verified custom domains fetched from `/sdk/validate` on `configure()`.

**Fix:** Verify the URL host is `aplnk.to`, a domain you declared locally, or one of your verified custom domains. A domain that is only fetched from the server is unknown until that request answers, so declare yours locally if a link has to resolve on a first launch.

```swift
// Pass WarpLink URLs (aplnk.to or a verified custom domain) to handleDeepLink.
// A URL on an unrecognized host comes back as .invalidURL.
WarpLink.handleDeepLink(url) { result in
    // ...
}
```

---

### `.linkNotFound`

**When:** The link slug does not exist, or the link has been deactivated or expired (HTTP 404).

**Fix:**
1. Verify the link exists in the [WarpLink dashboard](https://warplink.app)
2. Check that the link is active (not expired or disabled)
3. Ensure the slug in the URL matches

---

### `.passwordRequired`

**When:** The link is password protected (HTTP 403). Resolving it returns no destination and no platform URLs, because the password is checked in the browser and the app never sees it.

**Fix:** Open the short URL itself in a browser. The password form lives there, and a correct password redirects on to the destination.

```swift
case .passwordRequired:
    UIApplication.shared.open(tappedURL)
```

---

### `.decodingError(Error)`

**When:** The API response could not be parsed. This may indicate an SDK version mismatch with the API.

**Fix:** Update the SDK to the latest version. If the issue persists, enable `debugLogging` and report the error.

---

## Complete Error Handling Example

```swift
func handleWarpLinkError(_ error: WarpLinkError) {
    switch error {
    case .notConfigured:
        // Programming error: configure SDK earlier in app lifecycle
        assertionFailure("WarpLink SDK not configured")

    case .invalidApiKeyFormat:
        // Programming error: check API key format
        assertionFailure("Invalid WarpLink API key format")

    case .invalidApiKey:
        // API key revoked or incorrect
        showAlert("Authentication error. Please update the app.")

    case .networkError(let underlyingError):
        // No connectivity or timeout
        let nsError = underlyingError as NSError
        if nsError.code == NSURLErrorNotConnectedToInternet {
            showAlert("No internet connection. Please try again.")
        } else {
            showAlert("Network error. Please try again.")
        }

    case .serverError(let statusCode, _):
        if statusCode == 429 {
            // Rate limited. Back off.
            retryAfterDelay()
        } else {
            showAlert("Server error. Please try again later.")
        }

    case .invalidURL:
        // URL is not a WarpLink URL: ignore or log
        break

    case .linkNotFound:
        // Link deleted or expired
        showAlert("This link is no longer available.")

    case .passwordRequired:
        // Password checked in the browser, never in the app
        UIApplication.shared.open(tappedURL)

    case .decodingError:
        // SDK may be outdated
        showAlert("Please update the app to the latest version.")
    }
}
```

Usage:

```swift
WarpLink.handleDeepLink(url) { result in
    switch result {
    case .success(let deepLink):
        navigateTo(deepLink.destination)
    case .failure(let error):
        handleWarpLinkError(error)
    }
}
```

## Related Guides

- [API Reference](api-reference.md): `WarpLinkError` enum documentation
- [Troubleshooting](troubleshooting.md): common issues and solutions
