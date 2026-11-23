import Foundation

/// The debug lines that say what the deferred check decided and why. They name
/// the install date the SDK read, which is the value to compare against the
/// real install day when checking a device.
enum CheckGateLog {

    static func lines(
        installedAt: Date?,
        now: Date,
        age: InstallAge,
        policy: SDKPolicy,
        backoff: CheckBackoff?,
        verdict: CheckBackoff.Verdict?,
        gate: CheckGate,
        exempt: Bool
    ) -> [String] {
        var lines = [
            installLine(installedAt: installedAt, now: now, age: age, policy: policy),
            "Check gate: \(describe(gate))" + (exempt ? " (test key: limits not applied)" : ""),
        ]
        if let backoff = backoff, let verdict = verdict {
            lines.append(backoffLine(backoff, verdict: verdict))
        }
        return lines
    }

    // MARK: - Private

    private static func installLine(
        installedAt: Date?, now: Date, age: InstallAge, policy: SDKPolicy
    ) -> String {
        let limits = "no request after \(days(policy.maxInstallAge)) days, "
            + "no raw signals after \(hours(policy.rawSignalMaxInstallAge)) hours"
        guard let installedAt = installedAt else {
            return "Install age: install date unavailable (\(limits))"
        }
        let elapsed = days(now.timeIntervalSince(installedAt))
        return "Install age: installed \(iso(installedAt)), \(elapsed) days ago "
            + "(\(limits)), class: \(name(age))"
    }

    private static func backoffLine(_ backoff: CheckBackoff, verdict: CheckBackoff.Verdict) -> String {
        let base = "Failed checks: \(backoff.failures), last at \(iso(backoff.lastFailureAt))"
        switch verdict {
        case .allowed: return "\(base), next check allowed"
        case let .waiting(until): return "\(base), next check allowed at \(iso(until))"
        case .gaveUp: return "\(base), gave up"
        }
    }

    private static func describe(_ gate: CheckGate) -> String {
        switch gate {
        case .send(rawSignals: true): return "send with raw device signals"
        case .send(rawSignals: false): return "send without raw device signals"
        case .skip(.installTooOld): return "skip, install is too old"
        case .skip(.retryWait): return "skip, waiting after a failed check"
        case .skip(.gaveUp): return "skip, gave up after repeated failures"
        }
    }

    private static func name(_ age: InstallAge) -> String {
        switch age {
        case .unknown: return "unknown"
        case .fresh: return "fresh"
        case .rawSignalsOff: return "raw signals off"
        case .tooOld: return "too old"
        }
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func days(_ seconds: TimeInterval) -> String {
        String(format: "%.1f", seconds / 86_400)
    }

    private static func hours(_ seconds: TimeInterval) -> String {
        String(format: "%.1f", seconds / 3600)
    }
}
