import Foundation

/// How often the SDK may ask the server about an install, and for how long.
///
/// The SDK ships `defaults` and uses the last block the server sent in
/// `sdk_policy`. A server value is clamped, so a mistaken block can neither
/// silence the check nor make it run on every launch. Every instance is valid
/// by construction: `init` is the only way to make one and it clamps.
struct SDKPolicy: Equatable {

    /// Wait after each failed check, by failure count. The last delay repeats.
    let retryDelays: [TimeInterval]
    /// Stop asking once this long has passed since the first failed check.
    let giveUpAfter: TimeInterval
    /// An older install is not checked at all.
    let maxInstallAge: TimeInterval
    /// An install older than this is checked without raw device signals.
    let rawSignalMaxInstallAge: TimeInterval

    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 3600
    private static let day: TimeInterval = 86_400

    /// More delays than this are never read: the last one repeats anyway.
    static let maxDelayCount = 16

    static let defaults = SDKPolicy(
        retryDelays: [900, 3600, 21_600, 86_400],
        giveUpAfter: 3 * day,
        maxInstallAge: 30 * day,
        rawSignalMaxInstallAge: 2 * day
    )

    init(
        retryDelays: [TimeInterval],
        giveUpAfter: TimeInterval,
        maxInstallAge: TimeInterval,
        rawSignalMaxInstallAge: TimeInterval
    ) {
        let delays = retryDelays.prefix(Self.maxDelayCount)
            .map { Self.clamp($0, Self.minute, 7 * Self.day) }
        self.retryDelays = delays.isEmpty ? Self.defaults.retryDelays : delays
        self.giveUpAfter = Self.clamp(giveUpAfter, Self.hour, 30 * Self.day)
        let maxAge = Self.clamp(maxInstallAge, Self.day, 365 * Self.day)
        self.maxInstallAge = maxAge
        self.rawSignalMaxInstallAge = Self.clamp(rawSignalMaxInstallAge, Self.hour, maxAge)
    }

    /// The wait after `failures` failed checks (1 or more).
    func retryDelay(afterFailures failures: Int) -> TimeInterval {
        retryDelays[min(max(failures, 1) - 1, retryDelays.count - 1)]
    }

    /// Reads the `sdk_policy` object of a server answer. Nil when `value` is not
    /// an object or has no usable field, so the caller keeps what it has. A field
    /// that is missing or malformed takes its default, and the others still apply.
    static func parse(_ value: Any?) -> SDKPolicy? {
        guard let block = value as? [String: Any] else { return nil }
        let delays = delays(block["retry_delays_seconds"])
        let numbers = [
            "give_up_after_seconds", "max_install_age_seconds", "raw_signal_max_install_age_seconds",
        ].map { number(block[$0]) }
        guard delays != nil || numbers.contains(where: { $0 != nil }) else { return nil }
        let fallback = defaults
        return SDKPolicy(
            retryDelays: delays ?? fallback.retryDelays,
            giveUpAfter: numbers[0] ?? fallback.giveUpAfter,
            maxInstallAge: numbers[1] ?? fallback.maxInstallAge,
            rawSignalMaxInstallAge: numbers[2] ?? fallback.rawSignalMaxInstallAge
        )
    }

    /// The policy in the shape the server sends it, for storing.
    var wire: [String: Any] {
        [
            "retry_delays_seconds": retryDelays,
            "give_up_after_seconds": giveUpAfter,
            "max_install_age_seconds": maxInstallAge,
            "raw_signal_max_install_age_seconds": rawSignalMaxInstallAge,
        ]
    }

    // MARK: - Private

    private static func clamp(_ value: TimeInterval, _ low: TimeInterval, _ high: TimeInterval) -> TimeInterval {
        min(max(value, low), high)
    }

    private static func number(_ value: Any?) -> TimeInterval? {
        guard let number = (value as? NSNumber)?.doubleValue, number.isFinite else { return nil }
        return number
    }

    /// Every entry must be a number: a list with one bad entry is a bad list.
    private static func delays(_ value: Any?) -> [TimeInterval]? {
        guard let list = value as? [Any], !list.isEmpty else { return nil }
        let numbers = list.compactMap(number)
        return numbers.count == list.count ? numbers : nil
    }
}
