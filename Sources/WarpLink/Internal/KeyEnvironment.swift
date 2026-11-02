import Foundation

/// The environment an API key belongs to, which decides the device-state
/// namespace the SDK reads and writes.
///
/// A developer can run a `wl_test_` build and a `wl_live_` build on one device.
/// Test state lives under its own names, so Test never reads, writes or clears
/// what the live build stored. Production keeps the names every earlier release
/// used, so an upgrade resets nothing.
enum KeyEnvironment: Equatable {
    case production
    case test

    private static let testPrefix = "wl_test_"

    /// Any key that does not start with `wl_test_` is Production, as before.
    init(apiKey: String) {
        self = apiKey.hasPrefix(Self.testPrefix) ? .test : .production
    }

    /// `name` in this environment's namespace. Production returns it unchanged.
    func scoped(_ name: String) -> String {
        switch self {
        case .production: return name
        case .test: return "\(name)_test"
        }
    }
}
