import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Raw device signals collected for server-side fingerprint computation.
///
/// Per the attribution contract, the SDK sends only `accept_language` (raw
/// preferred language), `timezone_offset` (minutes, JS convention) and the IANA
/// `timezone` name. The
/// server derives the client IP and computes the fingerprint. User-Agent and
/// screen dimensions are intentionally NOT collected — they never match across
/// the browser/native-app and CSS-px/points boundaries.
struct DeviceSignals {
    let acceptLanguage: String
    let timezoneOffset: Int
    /// IANA zone name, e.g. "America/Toronto". Empty when unavailable.
    let timezone: String
}

/// Collects device signals for attribution fingerprinting.
///
/// Signals are sent raw to the server, which computes the fingerprint using the
/// client IP + these signals. The SDK does NOT hash locally.
final class FingerprintCollector {

    private let timeZone: TimeZone

    /// - Parameter timeZone: overridden by tests so the sign convention can be
    ///   asserted for a named zone; CI runs at UTC, where a flipped sign is
    ///   invisible.
    init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    /// The device's Identifier for Vendor (IDFV), used for the repeat check
    /// that recognizes an install asking again. Always available on iOS (no
    /// ATT required).
    /// Returns `nil` on non-UIKit platforms or rare edge cases (device restore).
    var idfv: String? {
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString
        #else
        return nil
        #endif
    }

    /// Collect device signals for attribution. Synchronous — no UI access.
    func collect() -> DeviceSignals {
        DeviceSignals(
            acceptLanguage: preferredLanguage(),
            timezoneOffset: timezoneOffset(),
            timezone: timeZone.identifier
        )
    }

    // MARK: - Private

    /// Raw device preferred language (e.g. `"en-US"`). Server normalizes;
    /// do NOT pre-normalize here.
    private func preferredLanguage() -> String {
        Locale.preferredLanguages.first ?? ""
    }

    /// Timezone offset in minutes, JS `getTimezoneOffset()` convention
    /// (sign-inverted, DST-aware): UTC+2 → -120.
    private func timezoneOffset() -> Int {
        -(timeZone.secondsFromGMT() / 60)
    }
}
