import XCTest
@testable import WarpLink

/// What a counted check keeps: the attempt number it took with its failure, and
/// the rule that it gives back only what it wrote.
final class CountedCheckTests: CheckTrafficTestCase {

    private func configureWithoutAutoCheck(key: String? = nil) {
        WarpLink.configure(apiKey: key ?? liveKey, options: TestSupport.noAuto)
    }

    // conformance: WL-S72

    func testTheCheckKeepsTheAttemptNumberItTook() {
        configureWithoutAutoCheck()

        let counted = CountedCheck.count(on: storage, at: clock)

        XCTAssertEqual(counted.attemptNumber, 1)
        XCTAssertEqual(storage.attemptNumber, 1)
    }

    // conformance: WL-S72

    func testAConfigureAfterTheCountStillGetsTheNumberBack() {
        configureWithoutAutoCheck()
        let generation = WarpLink.deferredCheckGeneration

        let counted = WarpLink.beginCountedCheck(store: storage, generation: generation)
        XCTAssertEqual(counted?.attemptNumber, 1)
        configureWithoutAutoCheck(key: testKey)

        XCTAssertEqual(storage.attemptNumber, 0, "the number the check took goes back with its failure")
        XCTAssertNil(storage.checkBackoff)
    }

    func testGivingBackLeavesANewerFailureAndNumberAlone() {
        configureWithoutAutoCheck()
        let older = CountedCheck.count(on: storage, at: clock)
        clock.addTimeInterval(900)
        let newer = CountedCheck.count(on: storage, at: clock)

        older.giveBack()

        XCTAssertEqual(storage.attemptNumber, 2)
        XCTAssertEqual(storage.checkBackoff?.failures, 2)
        newer.giveBack()
        XCTAssertEqual(storage.attemptNumber, 1, "the newest check still gives back its own")
        XCTAssertEqual(storage.checkBackoff?.failures, 1)
    }

    func testGivingBackAfterTheCountWasClearedKeepsTheNewNumber() {
        configureWithoutAutoCheck()
        let counted = CountedCheck.count(on: storage, at: clock)
        storage.clearCheckBackoff()
        storage.restoreAttemptNumber(7)

        counted.giveBack()

        XCTAssertNil(storage.checkBackoff)
        XCTAssertEqual(storage.attemptNumber, 7)
    }

    func testEndingTheLiveCheckClearsItsRecordAndKeepsTheFailure() {
        configureWithoutAutoCheck()
        let generation = WarpLink.deferredCheckGeneration
        _ = WarpLink.beginCountedCheck(store: storage, generation: generation)

        XCTAssertTrue(WarpLink.endCountedCheckIfCurrent(generation: generation))

        XCTAssertNil(WarpLink.countedCheck)
        XCTAssertEqual(storage.checkBackoff?.failures, 1, "the failure stays on the books")
    }

    func testEndingAnAbandonedCheckLeavesTheNewerCheckRecord() {
        configureWithoutAutoCheck()
        let abandoned = WarpLink.deferredCheckGeneration
        WarpLink.lock.lock()
        WarpLink.deferredCheckGeneration += 1
        WarpLink.lock.unlock()
        let newer = WarpLink.beginCountedCheck(store: storage, generation: WarpLink.deferredCheckGeneration)

        XCTAssertFalse(WarpLink.endCountedCheckIfCurrent(generation: abandoned))

        XCTAssertNotNil(newer)
        XCTAssertNotNil(WarpLink.countedCheck, "the newer check keeps its record")
    }
}
