import XCTest
@testable import WarpLink

/// The cross-launch wait after a failed check, and the point where the SDK
/// stops asking for this install.
final class CheckBackoffTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let policy = SDKPolicy.defaults

    func testTheFirstFailureWaitsTheFirstDelay() {
        let backoff = CheckBackoff.firstFailure(at: start)
        XCTAssertEqual(backoff.failures, 1)
        XCTAssertEqual(
            backoff.verdict(at: start.addingTimeInterval(899), policy: policy),
            .waiting(until: start.addingTimeInterval(900))
        )
        XCTAssertEqual(backoff.verdict(at: start.addingTimeInterval(900), policy: policy), .allowed)
    }

    // conformance: WL-S65

    func testEachFailureWaitsTheNextDelayFromItsOwnTime() {
        let schedule: [(failures: Int, wait: TimeInterval)] = [
            (1, 900), (2, 3600), (3, 21600), (4, 86400), (5, 86400),
        ]
        for (failures, wait) in schedule {
            let last = start.addingTimeInterval(100)
            let backoff = CheckBackoff(firstFailureAt: start, lastFailureAt: last, failures: failures)
            XCTAssertEqual(
                backoff.verdict(at: last.addingTimeInterval(wait - 1), policy: policy),
                .waiting(until: last.addingTimeInterval(wait)),
                "after \(failures) failures"
            )
            XCTAssertEqual(
                backoff.verdict(at: last.addingTimeInterval(wait), policy: policy), .allowed,
                "after \(failures) failures"
            )
        }
    }

    // conformance: WL-S66

    func testTheSdkGivesUpOnceTheGiveUpTimeHasPassedSinceTheFirstFailure() {
        let backoff = CheckBackoff(
            firstFailureAt: start,
            lastFailureAt: start.addingTimeInterval(200_000),
            failures: 5
        )
        XCTAssertEqual(
            backoff.verdict(at: start.addingTimeInterval(259_199), policy: policy),
            .waiting(until: start.addingTimeInterval(200_000 + 86_400))
        )
        XCTAssertEqual(backoff.verdict(at: start.addingTimeInterval(259_200), policy: policy), .gaveUp)
        XCTAssertEqual(backoff.verdict(at: start.addingTimeInterval(9_999_999), policy: policy), .gaveUp)
    }

    func testAFailureRecordedLaterKeepsTheFirstFailureTime() {
        let later = start.addingTimeInterval(5000)
        let backoff = CheckBackoff.firstFailure(at: start).recording(failureAt: later)
        XCTAssertEqual(backoff.firstFailureAt, start)
        XCTAssertEqual(backoff.lastFailureAt, later)
        XCTAssertEqual(backoff.failures, 2)
    }

    func testAClockSetBackNeverBlocksTheCheck() {
        let backoff = CheckBackoff.firstFailure(at: start)
        XCTAssertEqual(backoff.verdict(at: start.addingTimeInterval(-3600), policy: policy), .allowed)
    }

    func testTheServersDelaysApply() throws {
        let custom = try XCTUnwrap(SDKPolicy.parse(["retry_delays_seconds": [120]] as [String: Any]))
        let backoff = CheckBackoff.firstFailure(at: start)
        XCTAssertEqual(
            backoff.verdict(at: start.addingTimeInterval(119), policy: custom),
            .waiting(until: start.addingTimeInterval(120))
        )
        XCTAssertEqual(backoff.verdict(at: start.addingTimeInterval(120), policy: custom), .allowed)
    }

    func testItRoundTripsThroughItsStoredText() throws {
        let backoff = CheckBackoff(
            firstFailureAt: start, lastFailureAt: start.addingTimeInterval(60), failures: 3
        )
        let again = try XCTUnwrap(CheckBackoff(encoded: backoff.encoded))
        XCTAssertEqual(again, backoff)
    }

    func testStoredTextThatDoesNotParseIsNoBackoff() {
        for text in ["", "1,2", "a,b,c", "1,2,0", "1,2,-3", "1,2,3,4"] {
            XCTAssertNil(CheckBackoff(encoded: text), text)
        }
    }
}
