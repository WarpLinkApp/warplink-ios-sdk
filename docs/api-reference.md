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
public static let sdkVersion: String // "1.1.1"
```

The current SDK version string.

#### `isConfigured`

```swift
public static var isConfigured: Bool { get }
```

Whether the SDK has been configured via `configure(apiKey:options:)`. Thread-safe.

#### `isApiKeyValid`

```swift
public static var isApiKeyValid: Bool? { get }
```

The server's API-key validation verdict: `true` (valid), `false` (rejected/revoked), or `nil` (not yet determined). The SDK also logs a `[WarpLink] WARNING:` line when the key is rejected, even when `debugLogging` is off. Thread-safe.

#### `attributionResult`

```swift
public static var attributionResult: WarpLinkDeepLink? { get }
```

The cached deep link from the last completed deferred attribution check, or `nil`. Thread-safe.

### Methods

#### `configure(apiKey:options:)`

```swift
public static func configure(
    apiKey: String,
    options: WarpLinkOptions? = nil
)
```

Configure the SDK with your SDK key. Must be called before any other SDK methods. Call once, as early as possible.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `apiKey` | `String` | Your WarpLink **SDK key**, not an API key. Must match `wl_live_`/`wl_test_` + 32 alphanumeric characters. An API key resolves links but cannot record install attribution. |
| `options` | `WarpLinkOptions?` | Optional configuration. Defaults to all-features-on with no `onLink`. |

**Behavior:**
- Validates the SDK key format locally. If invalid, it reports `WarpLinkError.invalidApiKeyFormat` to `options.onLink`, always logs a warning, and returns without configuring.
- Initializes internal components and performs async server-side validation via `/sdk/validate`, caching the result for 24 hours. The validate response also supplies the org's verified link domains, which the SDK caches so custom-domain Universal Links resolve.
- Establishes the set of link domains synchronously: `aplnk.to`, plus `options.linkDomains`, plus the `WarpLinkDomains` Info.plist array. The server's list is added to that set when it arrives. Declare your custom domain in one of the two local places if a link on it has to resolve on a first launch, before the network has answered.
- If `options.autoDeferredCheck` is `true` (default), runs the deferred deep link check and routes the result to `options.onLink`.

**Example:**

```swift
WarpLink.configure(
    apiKey: "wl_live_yoursdkkeyhere000000000000000000",
    options: WarpLinkOptions(onLink: { result in /* cold, warm, or deferred */ })
)
```

---

#### `open(_:)`

```swift
@discardableResult
public static func open(_ url: URL) -> Bool
```

Deliver a `URL` to the SDK (host one-liner, e.g. SwiftUI `.onOpenURL`). Resolves the link and routes the result to `onLink`. Returns `true` if the URL was a WarpLink link the SDK will handle: a WarpLink domain **and** a path of exactly one segment, which is what a slug always is. No-op (returns `false`) when `autoDeepLinkHandling` is disabled, the URL is not on a WarpLink domain, or the path has more than one segment. Universal Links are registered for the whole domain, so pass every URL here and route the ones that return `false` with your own router.

```swift
.onOpenURL { WarpLink.open($0) }
```

---

#### `continue(_:)`

```swift
@discardableResult
public static func `continue`(_ userActivity: NSUserActivity) -> Bool
```

Deliver an `NSUserActivity` (Universal Link) to the SDK. Extracts `webpageURL` and forwards to `open(_:)`.

```swift
func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    WarpLink.continue(userActivity)
}
```

---

#### `handleDeepLink(_:completion:)`

```swift
public static func handleDeepLink(
    _ url: URL,
    completion: @escaping (Result<WarpLinkDeepLink, WarpLinkError>) -> Void
)
```

Resolve an incoming Universal Link URL and get the result inline (manual/advanced use). Independent of `autoDeepLinkHandling`. **Completion is always called on the main thread.**

**Errors:** `.notConfigured`, `.invalidURL`, `.linkNotFound`, `.passwordRequired`, `.networkError`, `.serverError`, `.invalidApiKey`, `.decodingError`.

---

#### `checkDeferredDeepLink(completion:)`

```swift
public static func checkDeferredDeepLink(
    completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
)
```

Run the deferred deep link check on demand (called for you when `autoDeferredCheck` is on). Returns `.success(nil)` when there is no match. **Completion is always called on the main thread.**

**Behavior:**
- Runs the attribution match until it completes (a definitive server response). After completion, returns the cached result without a network call.
- A failed attempt (e.g. offline) is not treated as complete, so a later call retries. The completion marker is scoped to one install, so a reinstall runs the check again and reports itself with `is_reinstall`.
- A matched deep link has `isDeferred: true` plus `matchType`, `matchConfidence`, and `matchGuaranteed`.

**Errors:** `.notConfigured`, `.networkError`, `.serverError`, `.invalidApiKey`, `.decodingError`.

---

## WarpLinkAppDelegate / WarpLinkSceneDelegate

Drop-in host delegates that forward incoming Universal Links to the SDK. No swizzling. Use directly, subclass, or copy the forwarding lines into your own delegate.

```swift
open class WarpLinkAppDelegate: UIResponder, UIApplicationDelegate
open class WarpLinkSceneDelegate: UIResponder, UIWindowSceneDelegate
```

- `WarpLinkAppDelegate` forwards `application(_:continue:restorationHandler:)` and `application(_:open:options:)`.
- `WarpLinkSceneDelegate` forwards `scene(_:willConnectTo:options:)` (cold launch), `scene(_:continue:)` (warm), and `scene(_:openURLContexts:)`.

Available on UIKit platforms.

---

## WarpLinkOptions

Configuration options for the SDK. Every feature is on by default (opt-out).

```swift
public struct WarpLinkOptions: Sendable
```

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `apiEndpoint` | `String` | `"https://api.warplink.app/v1"` | The API endpoint URL. |
| `debugLogging` | `Bool` | `false` | Enable `[WarpLink]` console logging. |
| `autoDeepLinkHandling` | `Bool` | `true` | Auto-resolve links from `open(_:)`/`continue(_:)` and route to `onLink`. Disable to use `handleDeepLink` yourself. |
| `autoDeferredCheck` | `Bool` | `true` | Auto-run the deferred check from `configure()` and route to `onLink`. Disable to call `checkDeferredDeepLink` yourself. |
| `linkDomains` | `[String]` | `[]` | Your link domains, e.g. `["links.yourbrand.com"]`. Recognized the moment `configure()` returns, so a link on a custom domain resolves on a first launch. Added to `aplnk.to` and to the server's list, never substituted for them. Bare hosts and full URLs both work. |
| `onLink` | `(@Sendable (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void)?` | `nil` | Single sink for all resolved links (cold, warm, deferred). Only a match or an error is delivered; a deferred no-match is suppressed, not dispatched to the sink. |

### Initializer

```swift
public init(
    apiEndpoint: String = "https://api.warplink.app/v1",
    debugLogging: Bool = false,
    autoDeepLinkHandling: Bool = true,
    autoDeferredCheck: Bool = true,
    linkDomains: [String] = [],
    onLink: (@Sendable (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void)? = nil
)
```

**Example:**

```swift
// The common shape: just a sink.
let options = WarpLinkOptions(onLink: handleLink)

// Opt out of everything and drive it manually.
let manual = WarpLinkOptions(autoDeepLinkHandling: false, autoDeferredCheck: false)

// A custom link domain, known before the network answers.
let custom = WarpLinkOptions(linkDomains: ["links.yourbrand.com"], onLink: handleLink)
```

### Declaring link domains in the Info.plist

The alternative to `linkDomains`, for teams that keep configuration out of code.
Add a `WarpLinkDomains` array of strings to your target's Info.plist:

```xml
<key>WarpLinkDomains</key>
<array>
    <string>links.yourbrand.com</string>
</array>
```

Both sources are read, and both are additive. Each entry may be a bare host or a
full URL; entries are trimmed and lowercased, and a URL is reduced to its host.

---

## WarpLinkDeepLink

Resolved deep link data returned by the SDK. Conforms to `Codable`, `Sendable`, and `Equatable`.

```swift
public struct WarpLinkDeepLink: Codable, Sendable, Equatable
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `linkId` | `String` | The unique identifier of the link. |
| `destination` | `String` | The resolved destination URL. |
| `deepLinkUrl` | `String?` | The iOS-specific deep link URL (e.g., `myapp://path`), if configured. |
| `customParams` | `[String: JSONValue]` | Custom parameters attached to the link. |
| `isDeferred` | `Bool` | Whether this deep link was resolved via deferred attribution. |
| `matchType` | `MatchType?` | The type of attribution match (`deterministic` or `probabilistic`). |
| `matchConfidence` | `Double?` | The confidence score of the attribution match (0.0 to 1.0). |
| `matchGuaranteed` | `Bool` | `true` only when the match was deterministic. Use it, like `matchConfidence`, to pick the destination to route to, not as a credential: a probabilistic match comes from a hashed match key built from the IP address and language, with time zone when available, so use it to route the user, not to identify them. Authenticate the user and check authorization separately before anything sensitive. |

### Working with `customParams`

`customParams` is `[String: JSONValue]`. `JSONValue` is a `Codable`/`Sendable` JSON wrapper. This is what makes `WarpLinkDeepLink` persistable and thread-safe (the old `[String: Any]` was neither). Read values with the typed accessors:

```swift
if case .success(let deepLink?) = result {
    let productId = deepLink.customParams["product_id"]?.stringValue
    let discount  = deepLink.customParams["discount"]?.doubleValue
    let featured  = deepLink.customParams["featured"]?.boolValue
}
```

---

## JSONValue

A `Codable`/`Sendable` JSON value type used for `customParams`.

```swift
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
}
```

### Accessors

| Accessor | Returns |
|----------|---------|
| `stringValue` | `String?` |
| `intValue` | `Int?` (coerces from `.double`) |
| `doubleValue` | `Double?` (coerces from `.int`) |
| `boolValue` | `Bool?` |
| `arrayValue` | `[JSONValue]?` |
| `objectValue` | `[String: JSONValue]?` |

---

## MatchType

The type of attribution match used to resolve a deferred deep link.

```swift
public enum MatchType: String, Codable, Sendable
```

| Case | Description |
|------|-------------|
| `.deterministic` | Matched by a deterministic signal, which the server returns only for a Play Install Referrer match. The IDFV repeat check never produces it. Confidence is 1.0 and `matchGuaranteed` is `true`. |
| `.probabilistic` | Matched via a server-side match key (first-install). Confidence is 0.20 to 0.85 by time since click, reduced further when the match key bucket was ambiguous or the click IP was widely shared. `matchGuaranteed` is always `false`. |

See [Attribution](attribution.md) for details on confidence scores.

---

## WarpLinkError

Typed errors for all SDK operations. Conforms to `Error` and `LocalizedError`.

```swift
public enum WarpLinkError: Error, LocalizedError
```

| Case | Description |
|------|-------------|
| `.notConfigured` | SDK used before `configure()` was called. |
| `.invalidApiKeyFormat` | SDK key format is invalid (`wl_live_`/`wl_test_` + 32 alphanumeric). |
| `.invalidApiKey` | SDK key was rejected by the server. It was revoked, mistyped, or is an API key. |
| `.networkError(Error)` | Network request failed with an underlying error. |
| `.serverError(statusCode: Int, message: String)` | API returned an error response. |
| `.invalidURL` | The URL is not a valid WarpLink Universal Link. |
| `.linkNotFound` | The link was not found (404) or is no longer active. |
| `.passwordRequired` | The link is password protected, so it resolves to no destination and no platform URLs. |
| `.decodingError(Error)` | Response parsing failed. |

Each case provides a localized description via `errorDescription`. See [Error Handling](error-handling.md) for recommended recovery actions.

## Thread Safety

- `WarpLink.isConfigured`, `isApiKeyValid`, and `attributionResult` are thread-safe (protected by `NSLock`).
- `onLink` and all completion handlers (`handleDeepLink`, `checkDeferredDeepLink`) are dispatched to the **main thread**.
- The SDK adds a light dedupe so the same URL delivered twice in a short window (auto delegate + a manual call) dispatches once.
- `configure()` can be called from any thread, but should be called once during app initialization.
