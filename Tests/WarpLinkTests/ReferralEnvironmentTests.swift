import XCTest
@testable import WarpLink

/// The referral stores in Test and live share one device and must not meet.
final class ReferralEnvironmentTests: XCTestCase {

    private let suiteName = "ReferralEnvironmentTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testEvidenceInOneEnvironmentIsInvisibleToTheOther() {
        let live = ReferralEvidenceStore(environment: .production, defaults: defaults)
        let test = ReferralEvidenceStore(environment: .test, defaults: defaults)
        live.remember(installId: "live-install")

        XCTAssertNil(test.evidence.installId)
        test.remember(token: "test-token", expiresAt: nil)
        XCTAssertNil(live.evidence.recoveryToken)
    }

    func testClearingTestEvidenceKeepsLiveEvidence() {
        let live = ReferralEvidenceStore(environment: .production, defaults: defaults)
        let test = ReferralEvidenceStore(environment: .test, defaults: defaults)
        live.remember(installId: "live-install")
        test.remember(installId: "test-install")

        test.clear()

        XCTAssertEqual(live.evidence.installId, "live-install")
        XCTAssertNil(test.evidence.installId)
    }

    func testLiveEvidenceKeepsThe1_2_0Name() {
        ReferralEvidenceStore(environment: .production, defaults: defaults).remember(installId: "i")

        XCTAssertNotNil(defaults.data(forKey: "warplink_referral_evidence"))
    }

    func testAPendingInvitationInOneEnvironmentIsInvisibleToTheOther() throws {
        let service = "app.warplink.sdk.tests.\(UUID().uuidString)"
        let markers = InMemoryMarkerStore()
        let live = KeychainPendingStore(environment: .production, service: service, installMarkers: markers)
        let test = KeychainPendingStore(environment: .test, service: service, installMarkers: markers)
        defer { live.clear(); test.clear() }
        let record = PendingRedemption(token: "t", expiresAt: .distantFuture)
        guard live.save(record) else { throw XCTSkip("The Keychain is not available to this test run.") }

        XCTAssertNil(test.load())
        test.clear()
        XCTAssertEqual(live.load()?.token, "t", "clearing Test leaves the live invitation")
    }
}
