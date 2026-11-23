import XCTest
@testable import WarpLink

/// The install-age rule on the shared check path: an old install sends nothing,
/// an install past the raw limit sends no raw signals, a test key is never limited.
final class InstallAgeCheckTests: CheckTrafficTestCase {

    private func install(agedBy age: TimeInterval) {
        installedAt = clock.addingTimeInterval(-age)
    }

    // conformance: WL-S63

    func testAnInstallOlderThanThirtyDaysSendsNothingAndAnswersNoMatch() {
        let transport = serving(CheckWire.matched)
        configure(transport)
        install(agedBy: 31 * day)

        assertNoMatch(check())

        XCTAssertEqual(matchCount(transport), 0)
    }

    // conformance: WL-S63

    func testTheSkipIsANoteOfItsOwnAndNeverTheCheckedGate() {
        let transport = serving(CheckWire.matched)
        let store = configure(transport)
        install(agedBy: 31 * day)

        check()

        XCTAssertTrue(store.wasSkippedForAge)
        XCTAssertFalse(store.isAttributionComplete, "the gate stays open")
        XCTAssertFalse(store.hasDeviceEverCompletedAttribution, "reinstall detection is untouched")
        XCTAssertFalse(store.isReinstall)
        XCTAssertNil(store.cachedAttribution)
    }

    func testAnInstallJustInsideThirtyDaysStillSendsWithoutRawSignals() throws {
        let transport = serving(CheckWire.noMatch)
        configure(transport)
        install(agedBy: 30 * day - 1)

        check()

        let body = try XCTUnwrap(matchBodies(transport).first)
        XCTAssertNil(body["accept_language"])
        XCTAssertNil(body["timezone_offset"])
        XCTAssertNil(body["timezone"])
        XCTAssertEqual(body["device_id"] as? String, deviceId, "the stronger path stays")
        XCTAssertEqual(body["platform"] as? String, "ios")
    }

    // conformance: WL-S64

    func testAnInstallPastFortyEightHoursSendsNoRawSignals() throws {
        let transport = serving(CheckWire.noMatch)
        configure(transport)
        install(agedBy: 49 * hour)

        check()

        let body = try XCTUnwrap(matchBodies(transport).first)
        XCTAssertNil(body["accept_language"])
        XCTAssertNil(body["timezone_offset"])
        XCTAssertEqual(body["device_id"] as? String, deviceId)
    }

    func testAnInstallInsideFortyEightHoursSendsRawSignals() throws {
        let transport = serving(CheckWire.noMatch)
        configure(transport)
        install(agedBy: 47 * hour)

        check()

        let body = try XCTUnwrap(matchBodies(transport).first)
        XCTAssertNotNil(body["accept_language"])
        XCTAssertNotNil(body["timezone_offset"])
    }

    func testAnUnreadableInstallDateLimitsNothing() throws {
        let transport = serving(CheckWire.noMatch)
        configure(transport)
        installedAt = nil

        check()

        XCTAssertNotNil(try XCTUnwrap(matchBodies(transport).first)["accept_language"])
    }

    // conformance: WL-S63

    func testATestKeyIsNeverLimitedByAge() throws {
        let transport = serving(CheckWire.noMatch)
        let store = configure(transport, key: testKey)
        install(agedBy: 400 * day)

        check()

        XCTAssertNotNil(try XCTUnwrap(matchBodies(transport).first)["accept_language"])
        XCTAssertFalse(store.wasSkippedForAge)
    }

    // conformance: WL-S64

    func testAnOldInstallWithNoStrongerPathSendsNothing() {
        let transport = serving(CheckWire.matched)
        let store = configure(transport)
        WarpLink.fingerprintCollector = FingerprintCollector(vendorIdentifier: { nil })
        install(agedBy: 5 * day)

        assertNoMatch(check())

        XCTAssertEqual(matchCount(transport), 0, "raw signals are off and there is no device id or code")
        XCTAssertFalse(store.wasSkippedForAge, "the install is not older than the install limit")
    }
}
