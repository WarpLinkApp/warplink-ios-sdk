import XCTest
@testable import WarpLink

/// A key the server REJECTS is a different failure from a malformed one: the
/// format check passes, so nothing throws and nothing is dispatched to `onLink`.
/// The SDK simply goes quiet, deep links stop resolving, and no attribution is
/// recorded.
///
/// The warning is the only signal a developer gets, so it has to be emitted
/// without `debugLogging`. It was untestable until `Logger` gained a sink,
/// which is why conformance WL-S12 sat open on iOS while Android had it.
final class ServerRejectionWarningTests: XCTestCase {

    private var defaults: UserDefaults!
    private var storage: Storage!
    private var lines: [String] = []

    private func makeLogger(debugEnabled: Bool) -> Logger {
        Logger(debugEnabled: debugEnabled) { [weak self] line in
            self?.lines.append(line)
        }
    }

    private var apiClient: APIClient {
        APIClient(
            apiKey: "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
            baseURL: "https://api.warplink.app/v1"
        )
    }

    override func setUp() {
        super.setUp()
        lines = []
        defaults = UserDefaults(suiteName: "ServerRejectionWarningTests")!
        defaults.removePersistentDomain(forName: "ServerRejectionWarningTests")
        storage = Storage(
            defaults: defaults,
            markerStore: InMemoryMarkerStore(),
            installMarkerStore: InMemoryMarkerStore()
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "ServerRejectionWarningTests")
        WarpLink.reset()
        super.tearDown()
    }

    private var warnings: [String] { lines.filter { $0.contains("WARNING:") } }

    // conformance: WL-S12
    func testRejectedKeyWarnsWithDebugLoggingOff() {
        WarpLink.handleValidationResult(
            .success(ValidationResult(valid: false, domains: [])),
            storage: storage,
            apiClient: apiClient,
            logger: makeLogger(debugEnabled: false)
        )

        XCTAssertTrue(
            warnings.contains { $0.contains("rejected by server") },
            "a server rejection must be visible without debug logging, got: \(lines)"
        )
    }

    // conformance: WL-S12
    func testAcceptedKeyDoesNotWarn() {
        // The control. Without it, warning on every path would look correct.
        WarpLink.handleValidationResult(
            .success(ValidationResult(valid: true, domains: [])),
            storage: storage,
            apiClient: apiClient,
            logger: makeLogger(debugEnabled: false)
        )

        XCTAssertTrue(warnings.isEmpty, "a valid key must not warn, got: \(lines)")
    }

    func testNetworkFailureDoesNotWarn() {
        // A transient network failure is not a misconfiguration. Warning here
        // would train developers to ignore the one message that matters.
        WarpLink.handleValidationResult(
            .failure(.networkError(URLError(.notConnectedToInternet))),
            storage: storage,
            apiClient: apiClient,
            logger: makeLogger(debugEnabled: false)
        )

        XCTAssertTrue(warnings.isEmpty, "a network failure must not warn, got: \(lines)")
    }
}
