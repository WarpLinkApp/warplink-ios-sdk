import Foundation

/// What one deferred check sends. Fixed for the whole check: every in-launch
/// retry, the pending-code resend and the test-code resend carry the same
/// values, apart from the Tether fields a resend changes.
struct DeferredCheckRequest {
    /// Raw device signals. Nil for an old install: only the stronger paths go.
    let signals: DeviceSignals?
    let deviceId: String?
    let isReinstall: Bool
    /// Which launch of this install sent a deferred check. Fixed for the launch.
    let attemptNumber: Int
    var tether: TetherRequestFields

    /// The same check with other Tether fields.
    func with(tether: TetherRequestFields) -> DeferredCheckRequest {
        var copy = self
        copy.tether = tether
        return copy
    }
}
