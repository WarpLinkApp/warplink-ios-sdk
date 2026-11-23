import Foundation

/// What the gate read at one moment, and the debug lines that explain it.
/// Reading it has no side effect: `WarpLink.recordCheckGate` logs it and notes
/// a skip for age.
struct CheckGateReading {
    let gate: CheckGate
    let age: InstallAge
    let verdict: CheckBackoff.Verdict?
    let lines: () -> [String]
}

extension WarpLink {

    /// Reads whether a deferred check may send now, without logging or storing
    /// anything. The check path and the status API share it.
    static func readCheckGate(store: Storage, environment: KeyEnvironment) -> CheckGateReading {
        let now = SDKEnvironment.now()
        let policy = store.policy
        let installedAt = SDKEnvironment.installDate()
        let age = InstallAge.classify(installedAt: installedAt, now: now, policy: policy)
        let backoff = store.checkBackoff
        let verdict = backoff?.verdict(at: now, policy: policy)
        let exempt = environment == .test
        let gate = CheckGate.decide(age: age, backoff: verdict, exempt: exempt)

        return CheckGateReading(gate: gate, age: age, verdict: verdict) {
            CheckGateLog.lines(
                installedAt: installedAt, now: now, age: age, policy: policy,
                backoff: backoff, verdict: verdict, gate: gate, exempt: exempt
            )
        }
    }

    /// Decides whether a deferred check may send now, and says why in the debug
    /// log. Call it once per check: it logs every time. A skip for age leaves
    /// its own note in storage. It never touches the checked gate or the
    /// device-seen marker, so reinstall detection stays right.
    static func decideCheckGate(store: Storage, environment: KeyEnvironment, log: Logger?) -> CheckGate {
        let reading = readCheckGate(store: store, environment: environment)
        recordCheckGate(reading, store: store, log: log)
        return reading.gate
    }

    /// Logs what the gate decided and notes a skip for age.
    static func recordCheckGate(_ reading: CheckGateReading, store: Storage, log: Logger?) {
        if let log = log, log.debugEnabled { reading.lines().forEach { log.log($0) } }
        if reading.gate == .skip(.installTooOld) { noteSkippedForAge(store) }
    }

    /// Writes the skipped-for-age note once.
    static func noteSkippedForAge(_ store: Storage) {
        if !store.wasSkippedForAge { store.markSkippedForAge() }
    }
}
