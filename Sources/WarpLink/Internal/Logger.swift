import Foundation

/// Internal debug logger. Only outputs when `debugEnabled` is true.
class Logger {

    let debugEnabled: Bool

    init(debugEnabled: Bool) {
        self.debugEnabled = debugEnabled
    }

    /// Log a message with the `[WarpLink]` prefix when debug is enabled.
    func log(_ message: String) {
        guard debugEnabled else { return }
        print("[WarpLink] \(message)")
    }

    /// Mask an API key for safe logging.
    ///
    /// Returns prefix + `****` + last 4 chars (e.g., `wl_live_****o5p6`).
    /// For keys shorter than prefix + 4, masks everything after the prefix.
    static func maskApiKey(_ key: String) -> String {
        let prefixes = ["wl_live_", "wl_test_"]
        for prefix in prefixes {
            guard key.hasPrefix(prefix) else { continue }
            let suffix = String(key.dropFirst(prefix.count))
            if suffix.count <= 4 {
                return "\(prefix)****"
            }
            let lastFour = String(suffix.suffix(4))
            return "\(prefix)****\(lastFour)"
        }
        // Unknown format — mask all but first 4 and last 4
        if key.count <= 8 {
            return "****"
        }
        return "\(key.prefix(4))****\(key.suffix(4))"
    }
}
