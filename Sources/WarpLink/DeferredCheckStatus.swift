import Foundation

/// Where the deferred deep link check stands for this install. It tells a check
/// that was skipped from a check that found no match.
///
/// Read it with `WarpLink.deferredCheckStatus`. Every state except `checking`
/// comes from what the SDK stored, so a relaunch keeps it.
public enum DeferredCheckStatus: Equatable, Sendable {
    /// No check has finished for this install yet. It also means a check failed
    /// and its wait has passed, so the next one may send.
    case notChecked
    /// A check is running, or waiting for the app to come to the foreground.
    case checking
    /// The check finished and found a link.
    case matched
    /// The check finished and found no link.
    case noMatch
    /// An earlier check failed. The next one is allowed from `retryAt`.
    case waiting(retryAt: Date)
    /// The install is older than the server's limit (30 days by default), so no
    /// request is sent.
    case skippedOldInstall
    /// The SDK gave up after repeated failures (3 days after the first one by
    /// default). No request is sent.
    case stopped
}

extension DeferredCheckStatus {

    /// Reads the status from storage and the check gate. A `wl_test_` key is
    /// never limited by age or backoff, so it reports none of the skip states.
    static func read(store: Storage, environment: KeyEnvironment, checking: Bool) -> DeferredCheckStatus {
        if store.isAttributionComplete { return store.cachedAttribution == nil ? .noMatch : .matched }
        if checking { return .checking }
        if environment == .test { return .notChecked }
        let reading = WarpLink.readCheckGate(store: store, environment: environment)
        // The note stands in for an install date that can no longer be read.
        // While the date is known, only the gate decides: a limit the server
        // raised since the skip no longer applies.
        if reading.age == .unknown, store.wasSkippedForAge { return .skippedOldInstall }
        switch (reading.gate, reading.verdict) {
        case (.skip(.installTooOld), _): return .skippedOldInstall
        case (.skip(.gaveUp), _): return .stopped
        case let (.skip(.retryWait), .waiting(until)?): return .waiting(retryAt: until)
        default: return .notChecked
        }
    }

    /// The text after `Deferred check: ` in the debug log.
    var logDescription: String {
        switch self {
        case .notChecked: return "notChecked"
        case .checking: return "checking"
        case .matched: return "matched"
        case .noMatch: return "noMatch"
        case let .waiting(retryAt): return "waiting, retry at \(ISO8601DateFormatter().string(from: retryAt))"
        case .skippedOldInstall: return "skippedOldInstall"
        case .stopped: return "stopped"
        }
    }
}

extension WarpLink {

    /// Where the deferred check stands for this install, read without sending
    /// anything. Use it to tell a skipped check from no match: `skippedOldInstall`
    /// and `stopped` mean no request was or will be sent, `noMatch` means the
    /// server looked and found nothing.
    public static var deferredCheckStatus: DeferredCheckStatus {
        lock.lock()
        let store = storage, key = apiKey, checking = deferredCheckInFlight
        lock.unlock()
        guard let store = store, let key = key else { return .notChecked }
        return .read(store: store, environment: KeyEnvironment(apiKey: key), checking: checking)
    }

    /// One debug line with the status a check ended in.
    static func logCheckOutcome() {
        lock.lock(); let log = logger; lock.unlock()
        guard let log = log, log.debugEnabled else { return }
        log.log("Deferred check: \(deferredCheckStatus.logDescription)")
    }
}
