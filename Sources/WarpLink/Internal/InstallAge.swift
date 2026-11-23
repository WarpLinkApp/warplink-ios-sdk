import Foundation

/// What the age of an install allows the SDK to send.
enum InstallAge: Equatable {
    /// The install date could not be read. Nothing is limited.
    case unknown
    case fresh
    /// Older than the raw-signal limit: the request goes without raw device
    /// signals and keeps the stronger paths (device id, Tether code).
    case rawSignalsOff
    /// Older than the install limit: no request at all.
    case tooOld

    static func classify(installedAt: Date?, now: Date, policy: SDKPolicy) -> InstallAge {
        guard let installedAt = installedAt else { return .unknown }
        let age = now.timeIntervalSince(installedAt)
        if age > policy.maxInstallAge { return .tooOld }
        if age > policy.rawSignalMaxInstallAge { return .rawSignalsOff }
        return .fresh
    }
}
