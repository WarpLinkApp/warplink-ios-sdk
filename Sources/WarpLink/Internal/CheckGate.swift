import Foundation

/// What a deferred check may do right now.
enum CheckGate: Equatable {

    /// Send the request, with or without raw device signals.
    case send(rawSignals: Bool)
    /// Send nothing. The check answers "no match" and the gate stays open.
    case skip(Reason)

    enum Reason: Equatable {
        case installTooOld
        case retryWait
        case gaveUp
    }

    /// Age is judged before the wait. A test key (`exempt`) is never limited,
    /// so a developer can run a first install again at any time.
    static func decide(age: InstallAge, backoff: CheckBackoff.Verdict?, exempt: Bool) -> CheckGate {
        if exempt { return .send(rawSignals: true) }
        if age == .tooOld { return .skip(.installTooOld) }
        switch backoff {
        case .gaveUp?: return .skip(.gaveUp)
        case .waiting?: return .skip(.retryWait)
        case .allowed?, nil: return .send(rawSignals: age != .rawSignalsOff)
        }
    }
}
