import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Raw device signals collected for server-side fingerprint computation.
struct DeviceSignals {
    let acceptLanguage: String
    let screenWidth: Int
    let screenHeight: Int
    let timezoneOffset: Int
    let userAgent: String
}

/// Collects device signals for attribution fingerprinting.
///
/// Signals are sent raw to the server, which computes the fingerprint
/// using the client IP + these signals. The SDK does NOT hash locally.
class FingerprintCollector {

    /// The device's Identifier for Vendor (IDFV), used for deterministic
    /// re-engagement matching. Always available on iOS (no ATT required).
    /// Returns `nil` on non-UIKit platforms or rare edge cases (device restore).
    var idfv: String? {
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString
        #else
        return nil
        #endif
    }

    /// Collect device signals for attribution.
    ///
    /// - Parameter completion: Called with device signals or an error.
    func collectFingerprint(
        completion: @escaping (Result<DeviceSignals, WarpLinkError>) -> Void
    ) {
        let acceptLanguage = buildAcceptLanguage()
        let timezoneOffset = computeTimezoneOffset()
        let userAgent = "WarpLink-iOS/\(WarpLink.sdkVersion)"

        collectScreenSize { width, height in
            let signals = DeviceSignals(
                acceptLanguage: acceptLanguage,
                screenWidth: width,
                screenHeight: height,
                timezoneOffset: timezoneOffset,
                userAgent: userAgent
            )
            completion(.success(signals))
        }
    }

    // MARK: - Private

    private func buildAcceptLanguage() -> String {
        return Locale.preferredLanguages.joined(separator: ",")
    }

    private func computeTimezoneOffset() -> Int {
        let secondsFromGMT = TimeZone.current.secondsFromGMT()
        return -(secondsFromGMT / 60)
    }

    private func collectScreenSize(
        completion: @escaping (_ width: Int, _ height: Int) -> Void
    ) {
        #if canImport(UIKit)
        if Thread.isMainThread {
            let bounds = UIScreen.main.bounds
            completion(Int(bounds.width), Int(bounds.height))
        } else {
            DispatchQueue.main.async {
                let bounds = UIScreen.main.bounds
                completion(Int(bounds.width), Int(bounds.height))
            }
        }
        #else
        completion(0, 0)
        #endif
    }
}
