import Foundation

/// Internal logger. `log` outputs only when `debugEnabled`; `warn` always
/// outputs, because a warning is the only signal a developer gets for a key
/// the server rejected.
class Logger {

    /// Where a line goes. `print` in production.
    ///
    /// It exists so a test can read what was emitted. The warnings this type
    /// produces are the ONLY signal a developer gets for a key the server
    /// rejected: the format check passed, so nothing throws, and the SDK then
    /// goes quietly dead. A bare `print()` cannot be asserted on, which left
    /// that path untested (conformance WL-S12) while every other failure mode
    /// was pinned.
    typealias Sink = (String) -> Void

    let debugEnabled: Bool
    private let sink: Sink

    init(debugEnabled: Bool, sink: @escaping Sink = { print($0) }) {
        self.debugEnabled = debugEnabled
        self.sink = sink
    }

    /// Log a message with the `[WarpLink]` prefix when debug is enabled.
    func log(_ message: String) {
        guard debugEnabled else { return }
        sink("[WarpLink] \(message)")
    }

    /// Surface a developer-facing warning (e.g. an invalid/revoked API key).
    /// Always emitted, regardless of `debugEnabled`, since these indicate a
    /// misconfiguration the developer must fix.
    func warn(_ message: String) {
        sink("[WarpLink] WARNING: \(message)")
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
