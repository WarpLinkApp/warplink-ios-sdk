import Foundation

/// What the SDK remembers about how often it asked the server for this install.
///
/// The per-install parts live in the install marker store, like the gate, so a
/// reinstall starts them over. None of it is the gate: a check that is skipped
/// or told to wait leaves `isAttributionComplete` and the device-seen marker alone.
extension Storage {

    // MARK: - Server policy

    /// The last valid `sdk_policy` the server sent, or the built-in defaults.
    var policy: SDKPolicy {
        guard let data = defaults.data(forKey: keys.sdkPolicy),
              let stored = SDKPolicy.parse(try? JSONSerialization.jsonObject(with: data))
        else { return .defaults }
        return stored
    }

    /// Keeps `policy` for the next launch. Nil, which is an answer with no
    /// valid block, keeps what is stored.
    func savePolicy(_ policy: SDKPolicy?) {
        guard let policy = policy,
              let data = try? JSONSerialization.data(withJSONObject: policy.wire) else { return }
        defaults.set(data, forKey: keys.sdkPolicy)
    }

    // MARK: - Attempts

    /// The number of launches of this install that sent a deferred check.
    var attemptNumber: Int {
        installMarkerStore.value(keys.attemptNumber).flatMap { Int($0) } ?? 0
    }

    /// Counts this launch's check as one that sent a request, and returns its number.
    func takeAttemptNumber() -> Int {
        let number = attemptNumber + 1
        installMarkerStore.write(keys.attemptNumber, value: String(number))
        return number
    }

    /// Puts back the number `takeAttemptNumber` advanced, for an abandoned check.
    func restoreAttemptNumber(_ previous: Int) {
        installMarkerStore.write(keys.attemptNumber, value: String(previous))
    }

    // MARK: - Failed checks

    var checkBackoff: CheckBackoff? {
        installMarkerStore.value(keys.checkBackoff).flatMap { CheckBackoff(encoded: $0) }
    }

    func recordCheckFailure(at time: Date) {
        let next = checkBackoff?.recording(failureAt: time) ?? .firstFailure(at: time)
        installMarkerStore.write(keys.checkBackoff, value: next.encoded)
    }

    /// Puts back what `recordCheckFailure` replaced. Nil is no failures.
    func restoreCheckBackoff(_ previous: CheckBackoff?) {
        guard let previous = previous else { return clearCheckBackoff() }
        installMarkerStore.write(keys.checkBackoff, value: previous.encoded)
    }

    func clearCheckBackoff() {
        installMarkerStore.clear(keys.checkBackoff)
    }

    // MARK: - Skipped for age

    /// Whether a check was skipped because this install is too old.
    var wasSkippedForAge: Bool {
        installMarkerStore.isMarked(keys.skippedForAge)
    }

    func markSkippedForAge() {
        installMarkerStore.mark(keys.skippedForAge)
    }

    /// Forgets the per-install check state. False entries could not be deleted.
    @discardableResult
    func clearCheckState() -> [Bool] {
        [
            installMarkerStore.clear(keys.attemptNumber),
            installMarkerStore.clear(keys.checkBackoff),
            installMarkerStore.clear(keys.skippedForAge),
            installMarkerStore.clear(keys.awaitingDelivery),
        ]
    }
}
