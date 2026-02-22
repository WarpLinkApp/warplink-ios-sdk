# Error Handling

The WarpLink SDK uses the `WarpLinkError` enum for all error cases. Every error conforms to `LocalizedError` and provides a human-readable `errorDescription`.

## Error Cases

### `.notConfigured`

**When:** Any SDK method is called before `WarpLink.configure(apiKey:options:)`.

**Fix:** Call `configure()` during app initialization — in your SwiftUI `App.init()` or UIKit `application(_:didFinishLaunchingWithOptions:)`.

```swift
// Ensure this runs before any handleDeepLink or checkDeferredDeepLink calls
WarpLink.configure(apiKey: "wl_live_your_api_key_here_abcdefgh")
```

---

### `.invalidApiKeyFormat`

**When:** The API key passed to `configure()` does not match the expected format: `wl_live_` or `wl_test_` followed by exactly 32 alphanumeric characters.

**Fix:** Verify your API key in the [WarpLink dashboard](https://warplink.app) under **Settings > API Keys**. Ensure you're copying the full key.

**Note:** This error does not surface through completion handlers — `configure()` silently returns without configuring the SDK. Enable `debugLogging` to see the warning in the console.

---

### `.invalidApiKey`

**When:** The server rejects the API key (HTTP 401 or 403). The key may be revoked, expired, or incorrect.

**Fix:**
1. Check that you're using the correct key (live vs. test)
2. Verify the key is still active in the dashboard
3. Generate a new key if the current one was revoked

---

### `.networkError(Error)`

**When:** A network request fails — no internet connectivity, DNS resolution failure, or request timeout.

**Fix:** Retry with exponential backoff. Check device connectivity before retrying.

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
| 401 | Unauthorized | Check API key |
| 403 | Forbidden | Check API key permissions |
| 429 | Rate limited | Retry after delay |
| 500 | Server error | Retry later, report if persistent |
| 503 | Service unavailable | Retry later |

```swift
case .failure(let error):
    if case .serverError(let statusCode, let message) = error {
        if statusCode == 429 {
            // Rate limited — retry after delay
        } else if statusCode >= 500 {
            // Server issue — retry later
        }
    }
```

---

### `.invalidURL`

**When:** A URL passed to `handleDeepLink(_:completion:)` is not a recognized WarpLink Universal Link. Currently, only the `aplnk.to` domain is recognized.

**Fix:** Verify the URL host is `aplnk.to`. If you're using a custom domain, note that custom domain support in the SDK requires a future update.

```swift
// Only pass WarpLink URLs to handleDeepLink
if url.host == "aplnk.to" {
    WarpLink.handleDeepLink(url) { result in
        // ...
    }
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

### `.decodingError(Error)`

**When:** The API response could not be parsed. This may indicate an SDK version mismatch with the API.

**Fix:** Update the SDK to the latest version. If the issue persists, enable `debugLogging` and report the error.

---

## Complete Error Handling Example

```swift
func handleWarpLinkError(_ error: WarpLinkError) {
    switch error {
    case .notConfigured:
        // Programming error — configure SDK earlier in app lifecycle
        assertionFailure("WarpLink SDK not configured")

    case .invalidApiKeyFormat:
        // Programming error — check API key format
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
            // Rate limited — back off
            retryAfterDelay()
        } else {
            showAlert("Server error. Please try again later.")
        }

    case .invalidURL:
        // URL is not a WarpLink URL — ignore or log
        break

    case .linkNotFound:
        // Link deleted or expired
        showAlert("This link is no longer available.")

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

- [API Reference](api-reference.md) — `WarpLinkError` enum documentation
- [Troubleshooting](troubleshooting.md) — common issues and solutions
