import XCTest
@testable import WarpLink

/// `WarpLink.deferredCheckStatus`: tells a skipped check from no match. Every
/// answer is read from what the SDK stored, so a relaunch keeps it.
final class DeferredCheckStatusTests: CheckTrafficTestCase {

    private var status: DeferredCheckStatus { WarpLink.deferredCheckStatus }

    private var offline: InlineTransport { serving { _ in CheckWire.offline } }

    private func failOnce(key: String? = nil) {
        configure(offline, key: key)
        check()
    }

    // conformance: WL-S74

    func testBeforeConfigureNothingHasBeenChecked() {
        XCTAssertEqual(status, .notChecked)
    }

    func testAFreshInstallHasNotBeenChecked() {
        configure(serving(CheckWire.noMatch))

        XCTAssertEqual(status, .notChecked)
    }

    func testAMatchReportsMatchedAndSurvivesARelaunch() {
        configure(serving(CheckWire.matched))
        check()
        XCTAssertEqual(status, .matched)

        relaunch()
        configure(serving(CheckWire.matched))
        XCTAssertEqual(status, .matched)
    }

    func testAnAnswerWithNoLinkReportsNoMatchAndSurvivesARelaunch() {
        configure(serving(CheckWire.noMatch))
        check()
        XCTAssertEqual(status, .noMatch)

        relaunch()
        configure(serving(CheckWire.noMatch))
        XCTAssertEqual(status, .noMatch)
    }

    func testACompletedCheckStaysCompletedWhateverTheClockAndInstallAgeSay() {
        configure(serving(CheckWire.matched))
        check()

        clock.addTimeInterval(400 * day)
        installedAt = clock.addingTimeInterval(-400 * day)

        XCTAssertEqual(status, .matched)
    }

    func testAFailedCheckReportsWhenTheNextOneIsAllowed() {
        failOnce()

        XCTAssertEqual(status, .waiting(retryAt: clock.addingTimeInterval(15 * 60)))
    }

    func testTheWaitSurvivesARelaunchAndEndsWhenItHasPassed() {
        failOnce()
        let retryAt = clock.addingTimeInterval(15 * 60)

        relaunch()
        configure(offline)
        XCTAssertEqual(status, .waiting(retryAt: retryAt))

        clock = retryAt
        XCTAssertEqual(status, .notChecked)
    }

    func testTheWaitGrowsWithEachFailure() {
        failOnce()
        clock.addTimeInterval(15 * 60)
        check()

        XCTAssertEqual(status, .waiting(retryAt: clock.addingTimeInterval(hour)))
    }

    func testGivingUpReportsStoppedAndSurvivesARelaunch() {
        failOnce()
        clock.addTimeInterval(3 * day)
        XCTAssertEqual(status, .stopped)

        relaunch()
        configure(offline)
        XCTAssertEqual(status, .stopped)
    }

    func testAnOldInstallReportsSkippedBeforeAnyCheckRuns() {
        installedAt = clock.addingTimeInterval(-31 * day)
        configure(serving(CheckWire.matched))

        XCTAssertEqual(status, .skippedOldInstall)
    }

    func testASkippedCheckKeepsReportingSkippedWhenTheInstallDateCannotBeRead() {
        installedAt = clock.addingTimeInterval(-31 * day)
        configure(serving(CheckWire.matched))
        assertNoMatch(check())

        relaunch()
        installedAt = nil
        configure(serving(CheckWire.matched))

        XCTAssertEqual(status, .skippedOldInstall)
    }

    func testARaisedServerLimitEndsTheSkipReport() {
        installedAt = clock.addingTimeInterval(-31 * day)
        configure(serving(CheckWire.matched))
        assertNoMatch(check())
        XCTAssertEqual(status, .skippedOldInstall)

        storage.savePolicy(SDKPolicy.parse(["max_install_age_seconds": 60 * 24 * 3600]))

        XCTAssertEqual(status, .notChecked)
    }

    func testAnOldInstallWithNothingToSendIsNotReportedAsTooOld() {
        let transport = serving(CheckWire.matched)
        configure(transport)
        WarpLink.fingerprintCollector = FingerprintCollector(vendorIdentifier: { nil })
        installedAt = clock.addingTimeInterval(-5 * day)
        assertNoMatch(check())
        XCTAssertEqual(matchCount(transport), 0)
        XCTAssertEqual(status, .notChecked)

        installedAt = nil
        XCTAssertEqual(status, .notChecked)
    }

    func testAnOldInstallThatAlsoFailedBeforeReportsSkippedNotWaiting() {
        failOnce()
        installedAt = clock.addingTimeInterval(-31 * day)

        XCTAssertEqual(status, .skippedOldInstall)
    }

    func testReadingTheStatusSendsNothingAndStoresNothing() {
        installedAt = clock.addingTimeInterval(-31 * day)
        let transport = serving(CheckWire.matched)
        configure(transport)

        _ = status

        XCTAssertEqual(matchCount(transport), 0)
        XCTAssertFalse(storage.wasSkippedForAge)
    }

    func testACheckWaitingForTheForegroundReportsChecking() {
        let transport = serving(CheckWire.matched)
        configure(transport)
        var start: (() -> Void)?
        SDKEnvironment.whenActive = { start = $0 }

        check()
        XCTAssertEqual(status, .checking)
        XCTAssertEqual(matchCount(transport), 0)

        SDKEnvironment.whenActive = { $0() }
        start?()
        XCTAssertEqual(status, .matched)
    }

    // MARK: - A test key

    func testATestKeyNeverReportsWaiting() {
        failOnce(key: testKey)

        XCTAssertEqual(status, .notChecked)
    }

    func testATestKeyNeverReportsStopped() {
        failOnce(key: testKey)
        clock.addTimeInterval(3 * day)

        XCTAssertEqual(status, .notChecked)
    }

    func testATestKeyNeverReportsSkippedOldInstall() {
        installedAt = clock.addingTimeInterval(-31 * day)
        configure(serving(CheckWire.matched), key: testKey)

        XCTAssertEqual(status, .notChecked)
    }

    func testATestKeyStillReportsItsAnswer() {
        installedAt = clock.addingTimeInterval(-31 * day)
        configure(serving(CheckWire.matched), key: testKey)
        check()

        XCTAssertEqual(status, .matched)
    }
}
