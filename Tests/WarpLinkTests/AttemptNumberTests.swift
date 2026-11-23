import XCTest
@testable import WarpLink

/// `attempt_number` counts the launches of this install that sent a deferred
/// check, not the retries inside one launch.
final class AttemptNumberTests: CheckTrafficTestCase {

    private func attemptNumbers(_ transport: InlineTransport) -> [Int?] {
        matchBodies(transport).map { $0["attempt_number"] as? Int }
    }

    // conformance: WL-S72

    func testTheFirstCheckSendsAttemptOne() {
        let transport = serving(CheckWire.noMatch)
        configure(transport)

        check()

        XCTAssertEqual(attemptNumbers(transport), [1])
    }

    func testInLaunchRetriesRepeatTheNumber() {
        let transport = serving { _ in CheckWire.offline }
        configure(transport)

        check()

        XCTAssertEqual(attemptNumbers(transport), [1, 1, 1])
    }

    // conformance: WL-S72

    func testEachLaunchThatSendsCountsOnce() {
        let transport = serving { _ in CheckWire.offline }
        configure(transport)

        check()
        clock.addTimeInterval(900)
        check()
        clock.addTimeInterval(3600)
        check()

        XCTAssertEqual(attemptNumbers(transport), [1, 1, 1, 2, 2, 2, 3, 3, 3])
        XCTAssertEqual(storage.attemptNumber, 3)
    }

    // conformance: WL-S72

    func testASkippedCheckDoesNotCount() {
        let transport = serving { _ in CheckWire.offline }
        configure(transport)

        check()
        clock.addTimeInterval(60)
        check()

        XCTAssertEqual(storage.attemptNumber, 1, "the second check sent nothing")
    }

    func testTheCountSurvivesAnAppRestart() {
        let transport = serving { _ in CheckWire.offline }
        configure(transport)
        check()

        relaunch()
        clock.addTimeInterval(900)
        configure(serving { _ in CheckWire.offline })
        check()

        XCTAssertEqual(storage.attemptNumber, 2)
    }
}
