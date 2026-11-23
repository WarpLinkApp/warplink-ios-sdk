import XCTest
@testable import WarpLink

/// The debug lines a developer reads on a device to check the install date the
/// SDK computed and what it decided, and the privacy manifest entry the date needs.
final class InstallAgeDiagnosticsTests: CheckTrafficTestCase {

    private func debugLines(key: String? = nil, installedDaysAgo days: Double) -> [String] {
        configure(serving(CheckWire.noMatch), key: key)
        let sink = Box<[String]>()
        sink.value = []
        WarpLink.logger = Logger(debugEnabled: true, sink: { sink.value?.append($0) })
        installedAt = clock.addingTimeInterval(-days * day)
        check()
        return sink.value ?? []
    }

    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    func testTheLogNamesTheInstallDateItsAgeAndTheDecision() {
        let lines = debugLines(installedDaysAgo: 3)

        let age = lines.first { $0.contains("Install age:") }
        XCTAssertTrue(age?.contains("installed \(iso(clock.addingTimeInterval(-3 * day)))") == true, "\(lines)")
        XCTAssertTrue(age?.contains("3.0 days ago") == true)
        XCTAssertTrue(age?.contains("class: raw signals off") == true)
        XCTAssertTrue(lines.contains { $0.contains("Check gate: send without raw device signals") })
    }

    func testTheLogSaysWhenAnInstallIsTooOld() {
        let lines = debugLines(installedDaysAgo: 40)

        XCTAssertTrue(lines.contains { $0.contains("class: too old") })
        XCTAssertTrue(lines.contains { $0.contains("Check gate: skip, install is too old") })
    }

    func testTheLogShowsWhatATestKeyWouldHaveDecidedAndThatItIsExempt() {
        let lines = debugLines(key: testKey, installedDaysAgo: 40)

        XCTAssertTrue(lines.contains { $0.contains("class: too old") })
        XCTAssertTrue(lines.contains { $0.contains("(test key: limits not applied)") })
    }

    func testTheLogSaysWhenTheInstallDateCannotBeRead() {
        configure(serving(CheckWire.noMatch))
        let sink = Box<[String]>()
        sink.value = []
        WarpLink.logger = Logger(debugEnabled: true, sink: { sink.value?.append($0) })
        installedAt = nil

        check()

        XCTAssertTrue(sink.value?.contains { $0.contains("install date unavailable") } == true)
    }

    func testTheLogShowsTheWaitAfterAFailedCheck() {
        configure(serving { _ in CheckWire.offline })
        check()
        let sink = Box<[String]>()
        sink.value = []
        WarpLink.logger = Logger(debugEnabled: true, sink: { sink.value?.append($0) })
        clock.addTimeInterval(60)

        check()

        XCTAssertTrue(sink.value?.contains { $0.contains("Failed checks: 1") && $0.contains("allowed at") } == true)
        XCTAssertTrue(sink.value?.contains { $0.contains("skip, waiting after a failed check") } == true)
    }

    func testThePrivacyManifestDeclaresTheFileTimestampReason() throws {
        let manifest = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/WarpLink/PrivacyInfo.xcprivacy")
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: manifest), format: nil) as? [String: Any]
        )
        let declared = try XCTUnwrap(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let timestamp = declared.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryFileTimestamp"
        }
        XCTAssertEqual(timestamp?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["C617.1"])
    }

    #if canImport(UIKit)
    /// Runs in an iOS test host, where the app container exists. The date it
    /// prints is the one the SDK would use for this install.
    func testTheRunningAppHasAnInstallDateInThePast() throws {
        let installed = try XCTUnwrap(InstallDate.ofRunningApp(), "the app container has no readable creation date")
        print("[WarpLink] install date read from the app container: \(iso(installed))")
        XCTAssertLessThanOrEqual(installed, Date())
    }
    #else
    func testWithoutAnAppContainerThereIsNoInstallDate() {
        XCTAssertNil(InstallDate.ofRunningApp())
    }
    #endif
}
