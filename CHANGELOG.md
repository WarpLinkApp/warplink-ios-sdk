# Changelog

All notable changes to the WarpLink iOS SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
