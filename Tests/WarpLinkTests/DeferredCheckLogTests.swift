import XCTest
@testable import WarpLink

/// What the debug log says about one deferred check: the gate decision and the
/// install age once, the request with its attempt number, and the outcome.
final class DeferredCheckLogTests: CheckTrafficTestCase {

    private let lines = Box<[String]>()

    override func setUp() {
        super.setUp()
        lines.value = []
    }

    private func captureLog() {
        WarpLink.logger = Logger(debugEnabled: true, sink: { [lines] in lines.value?.append($0) })
    }

    private func logged(_ fragment: String) -> [String] {
        (lines.value ?? []).filter { $0.contains(fragment) }
    }

    // conformance: WL-S75

    func testASendingCheckLogsTheGateDecisionAndInstallAgeOnce() {
        configure(serving(CheckWire.noMatch))
        captureLog()

        check()

        XCTAssertEqual(logged("Install age:").count, 1, "\(lines.value ?? [])")
        XCTAssertEqual(logged("Check gate:").count, 1)
    }

    func testASkippedCheckLogsTheGateDecisionAndInstallAgeOnce() {
        installedAt = clock.addingTimeInterval(-31 * day)
        configure(serving(CheckWire.noMatch))
        captureLog()

        check()

        XCTAssertEqual(logged("Install age:").count, 1, "\(lines.value ?? [])")
        XCTAssertEqual(logged("Check gate: skip, install is too old").count, 1)
    }

    func testACheckThatWaitsForTheForegroundLogsTheGateDecisionOnceWhenItStarts() {
        configure(serving(CheckWire.noMatch))
        captureLog()
        var start: (() -> Void)?
        SDKEnvironment.whenActive = { start = $0 }

        check()
        XCTAssertTrue(logged("Check gate:").isEmpty, "decided when the app is active, not before")

        SDKEnvironment.whenActive = { $0() }
        start?()
        XCTAssertEqual(logged("Check gate:").count, 1)
        XCTAssertEqual(logged("Install age:").count, 1)
    }

    func testThePendingRecheckLogsItsSkipOnce() {
        installedAt = clock.addingTimeInterval(-31 * day)
        configure(serving(CheckWire.noMatch))
        captureLog()

        XCTAssertEqual(WarpLink.pendingRecheckVerdict(), .done)

        XCTAssertEqual(logged("Check gate: skip, install is too old").count, 1, "\(lines.value ?? [])")
        XCTAssertEqual(logged("Install age:").count, 1)
        XCTAssertTrue(storage.wasSkippedForAge)
    }

    func testThePendingRecheckStaysSilentWhileAFailureIsWaitedOut() {
        configure(serving { _ in CheckWire.offline })
        check()
        captureLog()

        XCTAssertEqual(WarpLink.pendingRecheckVerdict(), .wait)

        XCTAssertTrue(logged("Check gate:").isEmpty)
    }

    func testACallParkedOnTheCheckInFlightAddsNoGateLines() {
        configure(serving(CheckWire.noMatch))
        captureLog()
        var start: (() -> Void)?
        SDKEnvironment.whenActive = { start = $0 }

        check()
        check()
        SDKEnvironment.whenActive = { $0() }
        start?()

        XCTAssertEqual(logged("Check gate:").count, 1, "\(lines.value ?? [])")
    }

    func testTheRequestLineNamesTheAttemptAndWhetherRawSignalsGo() {
        configure(serving(CheckWire.noMatch))
        captureLog()

        check()

        XCTAssertEqual(logged("Deferred check request:"), [
            "[WarpLink] Deferred check request: attempt 1, raw signals yes",
        ])
    }

    func testTheRequestLineSaysWhenRawSignalsAreLeftOut() {
        installedAt = clock.addingTimeInterval(-3 * day)
        configure(serving(CheckWire.noMatch))
        captureLog()

        check()

        XCTAssertEqual(logged("Deferred check request:"), [
            "[WarpLink] Deferred check request: attempt 1, raw signals no",
        ])
    }

    func testTheRequestLineCountsTheLaunchesThatSentARequest() {
        configure(serving { _ in CheckWire.offline })
        check()
        clock.addTimeInterval(15 * 60)
        captureLog()

        check()

        XCTAssertEqual(logged("Deferred check request: attempt 2").count, 1)
    }

    func testACheckThatSendsNothingLogsNoRequestLine() {
        installedAt = clock.addingTimeInterval(-31 * day)
        configure(serving(CheckWire.noMatch))
        captureLog()

        check()

        XCTAssertTrue(logged("Deferred check request:").isEmpty)
    }

    func testARetriedRequestIsStillOneRequestLine() {
        configure(serving { _ in CheckWire.offline })
        captureLog()

        check()

        XCTAssertEqual(logged("Deferred check request:").count, 1)
    }

    // MARK: - Outcome

    func testTheOutcomeNamesTheStatus() {
        configure(serving(CheckWire.matched))
        captureLog()

        check()

        XCTAssertEqual(logged("Deferred check: "), ["[WarpLink] Deferred check: matched"])
    }

    func testAFailedCheckLogsWhenItMayRetry() {
        configure(serving { _ in CheckWire.offline })
        captureLog()

        check()

        let retryAt = ISO8601DateFormatter().string(from: clock.addingTimeInterval(15 * 60))
        XCTAssertEqual(logged("Deferred check: "), ["[WarpLink] Deferred check: waiting, retry at \(retryAt)"])
    }

    func testASkippedCheckLogsItsStatus() {
        installedAt = clock.addingTimeInterval(-31 * day)
        configure(serving(CheckWire.noMatch))
        captureLog()

        check()

        XCTAssertEqual(logged("Deferred check: "), ["[WarpLink] Deferred check: skippedOldInstall"])
    }

    func testTheLogStaysSilentWithoutDebugLogging() {
        configure(serving(CheckWire.matched))
        var printed: [String] = []
        WarpLink.logger = Logger(debugEnabled: false, sink: { printed.append($0) })

        check()

        XCTAssertTrue(printed.isEmpty)
    }
}
