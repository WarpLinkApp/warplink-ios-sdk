import XCTest
@testable import WarpLink

/// How old an install is, and what the SDK may send for it.
final class InstallAgeTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let policy = SDKPolicy.defaults
    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 86_400

    private func classify(ageSeconds: TimeInterval) -> InstallAge {
        InstallAge.classify(installedAt: now.addingTimeInterval(-ageSeconds), now: now, policy: policy)
    }

    func testAFreshInstallSendsEverything() {
        XCTAssertEqual(classify(ageSeconds: 0), .fresh)
        XCTAssertEqual(classify(ageSeconds: 47 * hour), .fresh)
    }

    func testAnInstallOlderThanTheRawLimitSendsNoRawSignals() {
        XCTAssertEqual(classify(ageSeconds: 48 * hour), .fresh, "exactly at the limit is not older")
        XCTAssertEqual(classify(ageSeconds: 48 * hour + 1), .rawSignalsOff)
        XCTAssertEqual(classify(ageSeconds: 29 * day), .rawSignalsOff)
    }

    func testAnInstallOlderThanTheInstallLimitSendsNothing() {
        XCTAssertEqual(classify(ageSeconds: 30 * day), .rawSignalsOff, "exactly at the limit is not older")
        XCTAssertEqual(classify(ageSeconds: 30 * day + 1), .tooOld)
        XCTAssertEqual(classify(ageSeconds: 900 * day), .tooOld)
    }

    func testAnUnknownInstallDateChangesNothing() {
        XCTAssertEqual(InstallAge.classify(installedAt: nil, now: now, policy: policy), .unknown)
    }

    func testAnInstallDateInTheFutureIsFresh() {
        XCTAssertEqual(classify(ageSeconds: -5 * day), .fresh)
    }

    func testTheServersLimitsApply() throws {
        let custom = try XCTUnwrap(SDKPolicy.parse([
            "max_install_age_seconds": 10 * day,
            "raw_signal_max_install_age_seconds": 5 * hour,
        ] as [String: Any]))
        let at = { (age: TimeInterval) in
            InstallAge.classify(installedAt: self.now.addingTimeInterval(-age), now: self.now, policy: custom)
        }
        XCTAssertEqual(at(4 * hour), .fresh)
        XCTAssertEqual(at(6 * hour), .rawSignalsOff)
        XCTAssertEqual(at(11 * day), .tooOld)
    }

    func testTheContainerDateIsTheNewestOfTheDirectoriesItReads() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstallDateTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let older = root.appendingPathComponent("Documents")
        let newer = root.appendingPathComponent("Library")
        let missing = root.appendingPathComponent("Nothing")
        for url in [older, newer] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newDate = Date(timeIntervalSince1970: 1_750_000_000)
        try FileManager.default.setAttributes([.creationDate: oldDate], ofItemAtPath: older.path)
        try FileManager.default.setAttributes([.creationDate: newDate], ofItemAtPath: newer.path)

        XCTAssertEqual(InstallDate.newestCreation(of: [older, newer, missing]), newDate)
        XCTAssertEqual(InstallDate.newestCreation(of: [older, missing]), oldDate)
        XCTAssertNil(InstallDate.newestCreation(of: [missing]))
    }

    func testADateBeforeTheFirstIPhoneIsNotAnInstallDate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstallDateTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.creationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: root.path
        )
        XCTAssertNil(InstallDate.newestCreation(of: [root]))
    }
}
