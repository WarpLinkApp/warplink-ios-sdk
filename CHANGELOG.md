# Changelog

All notable changes to the WarpLink iOS SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
  Resolving one returns no destination and no platform URLs, because the password
  is checked in the browser and the app never sees it. Earlier versions reported
  that refusal as an invalid API key. Handle it by opening the short URL itself:
  the password form lives there, and a correct password redirects on to the
  destination. A link on a suspended custom domain reuses the existing
  `.linkNotFound`, so no second case was added.
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
  attribution body — they never matched across the browser/native boundary. The
  server computes the fingerprint from the request IP + these signals.
- **Attribution signals:** the body now also carries `timezone`, the IANA zone
  name (`TimeZone.current.identifier`), alongside `timezone_offset`. The zone name carries more entropy
  than a raw offset and does not shift at a daylight-saving boundary. The offset
  is still sent, and still used, when the server has no zone name for the click.
- **Match guarantee:** a resolved link now exposes `matchGuaranteed`. It is
  `true` only for a deterministic match (a real universal/app link, the install
  referrer, or a device-id match) and `false` for a probabilistic one. Gate
  auto-login, personal data, and anything else you cannot safely show the wrong
  person on this flag, not on the match alone.
- **Match window:** the deferred payload's default lifetime drops from 72 hours
  to 6, with a 24-hour ceiling. The probabilistic tier only. Deterministic
  matches are unaffected. A deferred link that is claimed more than 24 hours
  after the click will no longer match.
- **First-launch robustness:** the attribution flag is split into "attempted" vs
  "completed". Completion is recorded only on a definitive server response, so an
  offline first launch retries on the next launch.
- **Reinstalls are attributed again.** A reinstall counts as an install on every
  platform, so the completion marker is scoped to a single install: it lives in
  a file that is excluded from iCloud and iTunes backups, and it goes away with
  the app. Earlier versions kept a single first-launch flag in UserDefaults,
  which a backup restore carries, so a restored install was never attributed.
  Within one install the marker still guarantees at most one attribution. If
  that file cannot be written, the SDK falls back to a UserDefaults flag, which
  a restore does carry; in that rare case a restored install is not attributed
  again.
  A device that upgrades in place from 1.0.x runs the check once, as a first
  install: 1.0.x never recorded the install it came from, so there is nothing
  earlier for it to be a reinstall of.
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

- The inert `WarpLinkOptions.matchWindowHours` option. The match window is
  server-authoritative (set per link in the dashboard); there is no client-side
  match-window setting.

### Fixed

- An install is no longer stranded by an attribution response it cannot use. The
  deferred check is allowed to run once per install, and any 200 used to spend
  it, including a `matched` response that named no link and carried no
  destination. The SDK was right to discard such a response, but it then never
  asked again: the completion marker outlives every relaunch, so only deleting
  and reinstalling the app could clear it, and the install stayed unattributed
  for good. Such a response is now treated as unfinished business and retried on
  the next launch. A confirmed no-match is still definitive and still closes the
  check, exactly as before.
- A Universal Link whose path is not exactly one segment is no longer treated as
  a link. `https://<your-domain>/blog/hello` used to resolve as slug `blog`,
  which could open a completely unrelated destination, since a slug can never
  contain `/` anywhere else in the system. It now yields no slug, and
  `WarpLink.open(_:)` / `WarpLink.continue(_:)` return `false` for it so the URL
  falls through to your own router. This matters because the published
  `apple-app-site-association` covers every path on the domain, so iOS hands the
  app URLs the SDK was never able to resolve. A percent-encoded `%2F` inside a
  single segment is rejected for the same reason.
- An install upgrading from 1.0.x is attributed as a first install. 1.0.x wrote
  its first-launch flag at the start of the deferred check, before any request
  was sent, so the flag only ever proved that a check began. Reading it as proof
  of a completed attribution reported the upgrade's first attribution as a
  reinstall of an install that was never recorded. The flag is no longer read,
  and the 1.0.x UserDefaults keys are removed on the first launch of this
  version. The 1.0.x cached match is not migrated: `attributionResult` is nil
  for an upgrading user until their next install.
- A cached match that a backup restore brought back without its completion
  marker is cleared, so `attributionResult` no longer returns the previous
  install's match while the new check is in flight.
- The Keychain device-seen marker is written before anything is deleted. The old
  order erased a correct marker when the write failed, so the next reinstall
  was reported as a first install.
- The attempted marker is scoped to the install, like the completion marker. A
  restored device no longer logs a retry on its first launch.
- A tapped link that fails on a weak connection is retried. A resolve or a
  deferred check that fails with a dead or flaky connection, or with a 5xx, is
  now attempted up to three times, each attempt with its own time limit and the
  whole sequence limited to about twelve seconds. A weak connection usually
  delivers on the second attempt, in about eight. Every attempt of one tap
  carries the same identifier, so one tap still records one click. Refusals such
  as a missing link, a password protected link or an expired link are never
  retried.
- A tap arriving after the app was backgrounded long enough for its connection
  to die is now retried instead of failing outright. The OS reports that as
  `URLError(.cancelled)`, the same code a superseded tap gets on purpose, and
  the retry used to refuse both alike. A still-current attempt now retries a
  cancellation like any other weak-connection failure, on a fresh connection,
  while a superseded or abandoned one stays unretried exactly as before.
- A failed resolve now releases the duplicate-tap guard, so tapping the same
  link again straight after a failure really resolves it instead of being
  suppressed for the rest of the window. Android already behaved this way.
- The React Native bridge's resolve now stops the request it superseded instead
  of leaving it to run its full retry budget. A tap the bridge had already moved
  past could still succeed on the wire afterward and record a click for a link
  the app never delivered. Swift hosts calling `handleDeepLink(_:completion:)`
  directly are unaffected: this only changes the bridge's own internal resolve
  path, reached through an SPI the public API does not expose.

## [1.0.2] - 2026-06-26

### Added

- Privacy manifest (`PrivacyInfo.xcprivacy`). Declares the required-reason API usage (`UserDefaults`, reason `CA92.1`) and collected data (Device ID / IDFV, used for first-party install attribution, not for tracking) so apps that embed the SDK pass App Store privacy review.

## [1.0.1] - 2026-06-26

### Fixed

- The SDK now reports its correct version (`1.0.1`) in the `WarpLink-iOS/<version>` User-Agent. Earlier builds shipped a stale `sdkVersion` constant.

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
- Universal Link handling with `WarpLink.handleDeepLink(_:completion:)` — resolves links via `/links/resolve` API, returns destination URL, deep link URL, and custom parameters
- Deferred deep link resolution with `WarpLink.checkDeferredDeepLink(completion:)` — enriched fingerprint matching for first-install attribution with automatic first-launch detection and result caching
- Install attribution with two matching tiers:
  - Deterministic matching via IDFV (`UIDevice.current.identifierForVendor`) for re-engagement (confidence 1.0)
  - Probabilistic matching via enriched fingerprint (IP + User-Agent + Accept-Language + screen resolution + timezone) for first-install
- `WarpLinkOptions` for configurable settings: API endpoint, debug logging, and match window (default 72 hours)
- `WarpLinkDeepLink` response type with `linkId`, `destination`, `deepLinkUrl`, `customParams`, `isDeferred`, `matchType`, and `matchConfidence`
- `WarpLinkError` enum with 8 typed error cases and localized descriptions
- `MatchType` enum (`deterministic`, `probabilistic`) for attribution match classification
- SwiftUI and UIKit support (`.onOpenURL` and `SceneDelegate`/`AppDelegate` patterns)
- Debug logging with `[WarpLink]` prefix and API key masking
- Zero third-party dependencies — built entirely on Foundation and UIKit
