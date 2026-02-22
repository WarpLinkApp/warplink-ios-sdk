# API Reference

Complete reference for all public types and methods in the WarpLink iOS SDK.

## WarpLink

The main entry point for the SDK. All methods are static.

```swift
public final class WarpLink
```

### Properties

#### `sdkVersion`

```swift
public static let sdkVersion: String // "0.1.0"
```

The current SDK version string.

#### `isConfigured`

```swift
public static var isConfigured: Bool { get }
```

Whether the SDK has been configured via `configure(apiKey:options:)`. Thread-safe.

### Methods

#### `configure(apiKey:options:)`

```swift
public static func configure(
    apiKey: String,
    options: WarpLinkOptions? = nil
)
```

Configure the SDK with your API key. Must be called before any other SDK methods.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `apiKey` | `String` | Your WarpLink API key (e.g., `wl_live_xxx...`). Must match the format `wl_live_` or `wl_test_` followed by 32 alphanumeric characters. |
| `options` | `WarpLinkOptions?` | Optional configuration overrides. Defaults to `nil` (uses default options). |

**Behavior:**
- Validates API key format locally. If invalid, logs a warning (when `debugLogging` is enabled) and returns without configuring.
- On valid format, initializes internal components and performs async server-side API key validation via `/sdk/validate`.
- Server validation result is cached for 24 hours to avoid repeated network calls.

**Example:**

```swift
// Basic configuration
WarpLink.configure(apiKey: "wl_live_abcdefghijklmnopqrstuvwxyz012345")

// With options
WarpLink.configure(
    apiKey: "wl_live_abcdefghijklmnopqrstuvwxyz012345",
    options: WarpLinkOptions(debugLogging: true)
)
```

---

#### `handleDeepLink(_:completion:)`

```swift
public static func handleDeepLink(
    _ url: URL,
    completion: @escaping (Result<WarpLinkDeepLink, WarpLinkError>) -> Void
)
```

Handle an incoming Universal Link URL and resolve it to a deep link.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `url` | `URL` | The Universal Link URL received by the app. |
| `completion` | `(Result<WarpLinkDeepLink, WarpLinkError>) -> Void` | Called with the resolved deep link or an error. **Always called on the main thread.** |

**Errors:**
- `.notConfigured` — SDK not configured yet
- `.invalidURL` — URL is not a recognized WarpLink domain (`aplnk.to`)
- `.linkNotFound` — Link does not exist or is inactive
- `.networkError(Error)` — Network request failed
- `.serverError(statusCode:message:)` — API returned an error
- `.invalidApiKey` — API key rejected by server
- `.decodingError(Error)` — Response parsing failed

**Example:**

```swift
// SwiftUI
.onOpenURL { url in
    WarpLink.handleDeepLink(url) { result in
        switch result {
        case .success(let deepLink):
            print("Link ID: \(deepLink.linkId)")
            print("Destination: \(deepLink.destination)")
            if let deepLinkUrl = deepLink.deepLinkUrl {
                print("Deep link URL: \(deepLinkUrl)")
            }
        case .failure(let error):
            print("Error: \(error.localizedDescription)")
        }
    }
}
```

---

#### `checkDeferredDeepLink(completion:)`

```swift
public static func checkDeferredDeepLink(
    completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
)
```

Check for a deferred deep link on first launch. Returns `nil` in the success case if no match was found.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `completion` | `(Result<WarpLinkDeepLink?, WarpLinkError>) -> Void` | Called with the matched deep link (or `nil` if no match), or an error. **Always called on the main thread.** |

**Behavior:**
- On first launch: collects device signals (screen size, timezone, language, IDFV), sends them to the attribution API, and returns the match result.
- On subsequent launches: returns the cached result from the first check without a network call.
- The matched deep link has `isDeferred: true` and includes `matchType` and `matchConfidence`.

**Errors:**
- `.notConfigured` — SDK not configured yet
- `.networkError(Error)` — Network request failed
- `.serverError(statusCode:message:)` — API returned an error
- `.invalidApiKey` — API key rejected by server
- `.decodingError(Error)` — Response parsing failed

**Example:**

```swift
WarpLink.checkDeferredDeepLink { result in
    switch result {
    case .success(let deepLink):
        if let deepLink = deepLink {
            print("Deferred match: \(deepLink.destination)")
            print("Confidence: \(deepLink.matchConfidence ?? 0)")
        } else {
            print("No deferred deep link")
        }
    case .failure(let error):
        print("Error: \(error.localizedDescription)")
    }
}
```

---

## WarpLinkOptions

Configuration options for the SDK.

```swift
public struct WarpLinkOptions: Sendable
```

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `apiEndpoint` | `String` | `"https://api.warplink.app/v1"` | The API endpoint URL. Override for testing or custom deployments. |
| `debugLogging` | `Bool` | `false` | Enable debug logging with `[WarpLink]` prefix in the console. |
| `matchWindowHours` | `Int` | `72` | The match window in hours for deferred deep link attribution. |

### Initializer

```swift
public init(
    apiEndpoint: String = "https://api.warplink.app/v1",
    debugLogging: Bool = false,
    matchWindowHours: Int = 72
)
```

**Example:**

```swift
// Default options
let options = WarpLinkOptions()

// Custom options
let options = WarpLinkOptions(
    debugLogging: true,
    matchWindowHours: 48
)

WarpLink.configure(apiKey: "wl_live_...", options: options)
```

---

## WarpLinkDeepLink

Resolved deep link data returned by the SDK.

```swift
public struct WarpLinkDeepLink
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `linkId` | `String` | The unique identifier of the link. |
| `destination` | `String` | The resolved destination URL. |
| `deepLinkUrl` | `String?` | The iOS-specific deep link URL (e.g., `myapp://path`), if configured on the link. |
| `customParams` | `[String: Any]` | Custom parameters attached to the link. See note below. |
| `isDeferred` | `Bool` | Whether this deep link was resolved via deferred attribution. |
| `matchType` | `MatchType?` | The type of attribution match (`deterministic` or `probabilistic`). |
| `matchConfidence` | `Double?` | The confidence score of the attribution match (0.0 to 1.0). |

### Working with `customParams`

`customParams` is typed as `[String: Any]` because link parameters can contain mixed types (strings, numbers, booleans, nested objects). This type does not conform to `Codable`.

Use safe casting when accessing values:

```swift
WarpLink.handleDeepLink(url) { result in
    if case .success(let deepLink) = result {
        // Safe casting for custom parameters
        if let productId = deepLink.customParams["product_id"] as? String {
            showProduct(id: productId)
        }
        if let discount = deepLink.customParams["discount"] as? Double {
            applyDiscount(discount)
        }
    }
}
```

---

## MatchType

The type of attribution match used to resolve a deferred deep link.

```swift
public enum MatchType: String, Codable, Sendable
```

### Cases

| Case | Description |
|------|-------------|
| `.deterministic` | Matched via IDFV (re-engagement). Confidence is always 1.0. |
| `.probabilistic` | Matched via enriched fingerprint (first-install). Confidence varies by time window. |

See [Attribution](attribution.md) for details on confidence scores.

---

## WarpLinkError

Typed errors for all SDK operations. Conforms to `Error` and `LocalizedError`.

```swift
public enum WarpLinkError: Error, LocalizedError
```

### Cases

| Case | Description |
|------|-------------|
| `.notConfigured` | SDK used before `configure()` was called. |
| `.invalidApiKeyFormat` | API key format is invalid (must be `wl_live_` or `wl_test_` + 32 alphanumeric characters). |
| `.invalidApiKey` | API key was rejected by the server (revoked or incorrect). |
| `.networkError(Error)` | Network request failed with an underlying error. |
| `.serverError(statusCode: Int, message: String)` | API returned an error response. |
| `.invalidURL` | The URL is not a valid WarpLink Universal Link (not an `aplnk.to` domain). |
| `.linkNotFound` | The link was not found (404) or is no longer active. |
| `.decodingError(Error)` | Response parsing failed. |

Each case provides a localized description via `errorDescription`:

```swift
if case .serverError(let statusCode, let message) = error {
    print("Server error \(statusCode): \(message)")
}
// Or use the localized description
print(error.localizedDescription)
```

See [Error Handling](error-handling.md) for recommended recovery actions for each case.

## Thread Safety

- `WarpLink.isConfigured` is thread-safe (protected by `NSLock`).
- All completion handlers (`handleDeepLink`, `checkDeferredDeepLink`) are dispatched to the **main thread**.
- `configure()` can be called from any thread, but should be called once during app initialization.
