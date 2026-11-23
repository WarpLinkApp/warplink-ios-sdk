import XCTest
@testable import WarpLink

/// What a deferred check may do, given the install's age and its backoff.
final class CheckGateTests: XCTestCase {

    private let later = Date(timeIntervalSince1970: 1_800_000_900)

    func testNothingLimitingSendsWithRawSignals() {
        XCTAssertEqual(CheckGate.decide(age: .fresh, backoff: nil, exempt: false), .send(rawSignals: true))
        XCTAssertEqual(CheckGate.decide(age: .unknown, backoff: .allowed, exempt: false), .send(rawSignals: true))
    }

    func testAnOldInstallSendsWithoutRawSignals() {
        XCTAssertEqual(CheckGate.decide(age: .rawSignalsOff, backoff: nil, exempt: false), .send(rawSignals: false))
    }

    func testAnInstallPastTheLimitSkips() {
        XCTAssertEqual(CheckGate.decide(age: .tooOld, backoff: nil, exempt: false), .skip(.installTooOld))
    }

    func testTheWaitAndTheGiveUpSkip() {
        XCTAssertEqual(
            CheckGate.decide(age: .fresh, backoff: .waiting(until: later), exempt: false), .skip(.retryWait)
        )
        XCTAssertEqual(CheckGate.decide(age: .fresh, backoff: .gaveUp, exempt: false), .skip(.gaveUp))
    }

    func testAgeIsJudgedBeforeTheWait() {
        XCTAssertEqual(
            CheckGate.decide(age: .tooOld, backoff: .gaveUp, exempt: false), .skip(.installTooOld)
        )
    }

    func testATestKeyIsExemptFromEverything() {
        XCTAssertEqual(
            CheckGate.decide(age: .tooOld, backoff: .gaveUp, exempt: true), .send(rawSignals: true)
        )
        XCTAssertEqual(
            CheckGate.decide(age: .rawSignalsOff, backoff: .waiting(until: later), exempt: true),
            .send(rawSignals: true)
        )
    }
}
