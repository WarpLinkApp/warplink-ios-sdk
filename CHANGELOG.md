# Changelog

All notable changes to the WarpLink iOS SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2026-10-25

### Added

- **Referral invitations.** `WarpLink.redeemInvitation(text:completion:)` takes
  the text a person pastes during onboarding. If the text is a WarpLink
  invitation, the SDK matches it and returns the link in the completion. If it
  is anything else, the SDK sends nothing and returns `nil`, so onboarding stays
  usable after a skip, a failed copy or an overwritten clipboard.
- **Paste controls.** `WarpLinkPasteButton` (SwiftUI, iOS 16 and macOS 13) and
  `WarpLinkUIPasteButton` (UIKit, iOS 16) hand the pasted text to the SDK. They
  use the system paste control, so the person taps to allow each paste. The SDK
  never reads the clipboard on its own.
- **Bounded retry.** When a pasted invitation fails on the network, the SDK
  keeps it on the device and tries again on a later launch. It tries at most
  five times, counting every run that sends the invitation, whether it
  succeeds, fails or is cut off. It stops at the invitation's own expiry and
  delivers one invitation once.
- **Clear errors.** An expired or invalid invitation fails with
  `WarpLinkError.serverError` and a message that tells the person to reopen or
  replace the invitation. No new error case is added, so existing exhaustive
  `switch` statements keep compiling.
- **`WarpLink.claimReferral(installerId:completion:)`.** Claims the referral for
  the new installer. The call is safe to repeat. When there is nothing to claim
  it returns `ReferralClaimResult.Status.none` and no error.
  `ReferralClaimResult` has a public initializer, so a host or a plugin can
  build one in its own tests. Every field except `status` has a default.
- **Match evidence on `WarpLinkDeepLink`.** New optional fields: `attributionId`,
  `matchMethod`, `evidenceClass`, `replayState`, `capturedParams` and
  `tappedAt`. A match made from a link id alone reports `legacyLink`, so it stays
  distinct from a match backed by an invitation. Payloads cached by earlier
  versions still decode, and a value this version does not know decodes to `nil`.

## [1.1.1] - 2026-10-10

### Changed

- **Rate limits are retried once.** When the link resolve or the attribution
  match answers `429` with a `Retry-After` of 5 seconds or less, the SDK waits
  that long and sends the request one more time. With no readable `Retry-After`
  it waits 1 second. A longer `Retry-After` is not retried. If the retry is also
  refused, or the `Retry-After` is longer than 5 seconds, the call fails with
  `WarpLinkError.serverError` and `statusCode` 429. No new error case is added,
  so existing exhaustive `switch` statements keep compiling.

### Match guarantee

`matchGuaranteed` marks a deterministic match. Use it, like a confidence
threshold, to pick the destination the attribution result routes to. Keep
sign-in on your own authentication.

The IDFV lookup answers the same install asking again and returns the install
the device already has, with that install's own match type and confidence.

## [1.1.0] - 2026-09-15

Additive, opt-out release. A single `configure(apiKey:options:)` with an `onLink`
sink now makes deep linking, deferred deep linking, and attribution work
automatically. All existing manual methods remain, so upgrading is non-breaking
except for the `customParams` value type (see below).

### Added

- Opt-out configuration: `WarpLinkOptions` gains `autoDeepLinkHandling` (default
  `true`), `autoDeferredCheck` (default `true`), and a single `onLink` sink that
  receives cold-start, warm-start, and deferred results (disambiguate via
  `WarpLinkDeepLink.isDeferred`; a deferred no-match is suppressed and not
  dispatched to the sink, so only a match or an error reaches `onLink`).
- Host one-liners `WarpLink.open(_:)` and `WarpLink.continue(_:)`, plus drop-in
  `WarpLinkAppDelegate` / `WarpLinkSceneDelegate` that forward Universal Links to
  the SDK. No method swizzling. A light dedupe prevents double-dispatch of the
  same URL (auto + manual).
- The deferred deep link check auto-fires from `configure()` (once attribution is
  still pending) and routes to `onLink`.
- Custom-domain support: the SDK caches the org's verified link domains from
  `/sdk/validate` and resolves Universal Links on those hosts (no longer hardcoded
  to `aplnk.to`).
- Declare your link domains locally, so a custom-domain link resolves on a first
  launch. `WarpLinkOptions.linkDomains` takes them in code, and a
  `WarpLinkDomains` array of strings in your Info.plist takes them without code.
  Both are optional and both are additive: the effective set is `aplnk.to` plus
  what you declare plus what the server returns, so an integration that declares
  nothing behaves exactly as before. This matters because `WarpLink.open(_:)`
  has to answer "is this link mine?" the instant iOS hands the URL over, and on
  a first launch, or offline, the server's list has not arrived. Entries may be
  a bare host or a full URL; they are trimmed and lowercased, and a URL is
  reduced to its host. `www.` is preserved, since it is a different host.
- `WarpLink.isApiKeyValid` surfaces the server's key-validation verdict, and an
  invalid/revoked key logs a `[WarpLink] WARNING:` line even without debug logging.
- `WarpLinkDeepLink` is now `Codable`, `Sendable`, and `Equatable`. A new public
  `JSONValue` type backs `customParams`.
- Attribution requests now carry `app_bundle_id`, read from
  `Bundle.main.bundleIdentifier`. An API key is scoped to an organization rather
  than to one app, and every app signed by the same Apple team shares a single
  IDFV, so an organization shipping more than one app could have an install
  attributed to a sibling app. The bundle ID tells the server which app the
  install actually happened in. Nothing to configure; the field is omitted when
  the host has no bundle identifier.
- Attribution requests now carry `is_reinstall`, which is `true` when this device
  completed WarpLink attribution once before under an earlier install. It is
  derived from a Keychain marker that outlives an app delete and a backup
  restore, and that gates nothing. Installs and reinstalls are still counted
  together; the flag only lets them be told apart afterwards.
- Privacy manifest declares `NSPrivacyAccessedAPICategorySystemBootTime` with
  reason `35F9.1`. The deep-link dedupe window now reads
  `ProcessInfo.systemUptime`, which is a required-reason API, so an app that
  embedded this release without the declaration would be rejected at upload with
  ITMS-91053. The reading is compared in process, never persisted and never sent
  off device, as `35F9.1` requires.
- `WarpLinkError.passwordRequired`, a named case for a password protected link.
  Resolving one returns no destination and no platform URLs, because the
  password is checked in the browser and the app never sees it. Handle it by
  opening the short URL itself: the password form lives there, and a correct
  password redirects on to the destination. A link on a suspended custom domain
  reuses the existing `.linkNotFound`, so no second case was added.
- **`WarpLink.isWarpLinkURL(_:)`** answers whether a URL is a WarpLink Universal
  Link the SDK would claim: a host in the known link-domain set, and a path that
  carries a slug. It is the check `WarpLink.open(_:)` already makes before it
  touches its duplicate suppression, exposed for a host that forwards every
  incoming URL and needs to make the same decision at the same point. It
  resolves nothing, claims nothing and touches no network. Before
  `configure(apiKey:options:)` the known set is `aplnk.to` alone, so a
  custom-domain link reads as `false` until it has been declared or the server
  has returned it.

### Changed

- **Attribution signals:** the SDK now sends only `accept_language` (raw preferred
  language) and `timezone_offset` (minutes, JS convention), plus optional
  `device_id` (IDFV). **Removed** `user_agent` and screen width/height from the
  attribution body. The server computes the fingerprint from the request IP +
  these signals.
- **Attribution signals:** the body now also carries `timezone`, the IANA zone
  name (`TimeZone.current.identifier`), alongside `timezone_offset`. The zone name carries more entropy
  than a raw offset and does not shift at a daylight-saving boundary. The offset
  is still sent, and still used, when the server has no zone name for the click.
- **Match guarantee:** a resolved link now exposes `matchGuaranteed`. It is
  `true` only for a deterministic match (a real universal/app link or the install
  referrer) and `false` for a probabilistic one.
- **Match window:** the deferred payload's default lifetime drops from 72 hours
  to 6, with a 24-hour ceiling. The probabilistic tier only. Deterministic
  matches are unaffected.
- **First-launch robustness:** the attribution flag is split into "attempted" vs
  "completed". Completion is recorded only on a definitive server response, so an
  offline first launch retries on the next launch.
- **Reinstalls are attributed again.** A reinstall counts as an install on every
  platform, so the completion marker is scoped to a single install: it lives in
  a file that is excluded from iCloud and iTunes backups, and it goes away with
  the app. Within one install the marker still guarantees at most one
  attribution. A device that upgrades in place from 1.0.x
  runs the check once, as a first install.
- **`customParams` type:** changed from `[String: Any]` to `[String: JSONValue]`.
  Read values with typed accessors, e.g. `customParams["id"]?.stringValue`.
  (Source-breaking for code that cast `customParams["x"] as? String`.)
- **The tapped URL's parameters now reach the resolved link.** The SDK forwards
  the tapped URL's query string when it resolves a link, so `WarpLinkDeepLink`'s
  `destination` and `deepLinkUrl` carry the link's UTM and custom parameters
  exactly as a browser redirect would, and `customParams` is the full parameter
  set on the resolved destination rather than an empty dictionary.
- **Resolved URLs are normalized like redirected ones.** `WarpLinkDeepLink`'s
  `destination` and the platform URLs come back shaped exactly the way the
  redirect path shapes them, so a bare origin arrives carrying its trailing
  slash, and `customParams` now includes the query parameters already present on
  the stored destination. Both were always true of a browser redirect. A resolve
  simply matches it now, which is a server-side change with nothing to configure.
- **In-app opens are now recorded as clicks.** An app that opens a link directly
  through verified Universal Links previously produced no click. Those opens now
  appear in analytics, alongside the redirects that reach the link in a browser,
  and they count toward your plan's click allowance. This is a server-side
  change, so it applies to 1.0.x hosts too, and there is nothing to configure.
- `WarpLink.sdkVersion` now reports `1.1.0`.

### Removed

- The `WarpLinkOptions.matchWindowHours` option. The match window is
  server-authoritative (set per link in the dashboard); there is no client-side
  match-window setting.

### Fixed

- Installs retry attribution on the next launch when a response names no link.
- A Universal Link whose path is not exactly one segment, such as
  `https://<your-domain>/blog/hello`, yields no slug. `WarpLink.open(_:)` and
  `WarpLink.continue(_:)` return `false` for it so the URL falls through to your
  own router. This matters because the published `apple-app-site-association`
  covers every path on the domain, so iOS hands the app URLs the SDK was never
  able to resolve. A percent-encoded `%2F` inside a single segment is rejected
  for the same reason.
- An install upgrading from 1.0.x is attributed as a first install. The flag is
  no longer read, and the 1.0.x UserDefaults keys are removed on the first launch
  of this version. The 1.0.x cached match is not migrated: `attributionResult`
  is nil for an upgrading user until their next install.
- A restored install clears its cached match.
- The Keychain device-seen marker is written before anything is deleted.
- The attempted marker is scoped to the install, like the completion marker.
- A tapped link that fails on a weak connection is retried. A resolve or a
  deferred check that fails with a dead or flaky connection, or with a 5xx, is
  now attempted up to three times, each attempt with its own time limit and the
  whole sequence limited to about twelve seconds. Every attempt of one tap
  carries the same identifier, so one tap still records one click. Refusals such
  as a missing link, a password protected link or an expired link are never
  retried.
- A tap arriving after a long background is retried on a fresh connection. A
  superseded or abandoned tap is not retried.
- A failed resolve releases the duplicate-tap guard, so tapping the same link
  again resolves it.
- The React Native bridge's resolve stops the request it superseded, instead of
  leaving it to run its full retry budget. Swift hosts calling
  `handleDeepLink(_:completion:)` directly are unaffected: this only changes the
  bridge's own internal resolve path, reached through an SPI the public API does
  not expose.

### Migration: `customParams` is now `[String: JSONValue]`

`WarpLinkDeepLink.customParams` changed type in 1.1.0 from `[String: Any]` to
`[String: JSONValue]`. This breaks source: code that casts a value no longer
compiles. Read values through the typed accessors on `JSONValue` instead.

```swift
// 1.0.x
let id = link.customParams["id"] as? String
let count = link.customParams["count"] as? Int

// 1.1.0
let id = link.customParams["id"]?.stringValue
let count = link.customParams["count"]?.intValue
```

The accessors are `stringValue`, `intValue`, `doubleValue`, `boolValue`,
`arrayValue`, and `objectValue`. Each returns `nil` when the value has another
type. `foundationValue` lowers a value to plain Foundation types (`String`,
`Int`, `Double`, `Bool`, `[String: Any]`, `[Any]`, `NSNull`) for code that still
needs `Any`. To convert the whole dictionary:
`link.customParams.mapValues { $0.foundationValue }`.

## [1.0.2] - 2026-06-26

### Added

- Privacy manifest (`PrivacyInfo.xcprivacy`). Declares the required-reason API usage (`UserDefaults`, reason `CA92.1`) and collected data (Device ID / IDFV, used for first-party install attribution, not for tracking) so apps that embed the SDK pass App Store privacy review.

## [1.0.1] - 2026-06-26

### Fixed

- The SDK reports `1.0.1` in the `WarpLink-iOS/<version>` User-Agent.

### Changed

- Releases are now cut by a tag-driven workflow that creates the GitHub Release automatically.

## [1.0.0] - 2026-06-17

### Changed

- First stable release. Promotes the 0.1.0 API surface to 1.0.0 with semantic
  versioning guarantees. No breaking changes: existing integrations upgrade by
  bumping the package requirement to `from: "1.0.0"`.
- `WarpLink.sdkVersion` now reports `1.0.0` (sent as the `sdk_version` field and
  in the `WarpLink-iOS/<version>` User-Agent on attribution requests).

## [0.1.0] - 2026-02-09

### Added

- SDK initialization with `WarpLink.configure(apiKey:options:)` including local API key format validation (`wl_live_`/`wl_test_` prefix + 32 alphanumeric characters) and async server-side validation via `/sdk/validate` with 24-hour cache
- Universal Link handling with `WarpLink.handleDeepLink(_:completion:)`: resolves links via `/links/resolve` API, returns destination URL, deep link URL, and custom parameters
- Deferred deep link resolution with `WarpLink.checkDeferredDeepLink(completion:)`: enriched fingerprint matching for first-install attribution with automatic first-launch detection and result caching
- Install attribution with two matching tiers:
  - Deterministic matching via IDFV (`UIDevice.current.identifierForVendor`) for re-engagement (confidence 1.0)
  - Probabilistic matching via enriched fingerprint (IP + User-Agent + Accept-Language + screen resolution + timezone) for first-install
- `WarpLinkOptions` for configurable settings: API endpoint, debug logging, and match window (default 72 hours)
- `WarpLinkDeepLink` response type with `linkId`, `destination`, `deepLinkUrl`, `customParams`, `isDeferred`, `matchType`, and `matchConfidence`
- `WarpLinkError` enum with 8 typed error cases and localized descriptions
- `MatchType` enum (`deterministic`, `probabilistic`) for attribution match classification
- SwiftUI and UIKit support (`.onOpenURL` and `SceneDelegate`/`AppDelegate` patterns)
- Debug logging with `[WarpLink]` prefix and API key masking
- Zero third-party dependencies, built entirely on Foundation and UIKit
