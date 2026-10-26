import XCTest
@testable import WarpLink

/// The evidence store is read and written from the claim and redeem paths,
/// which can run on different queues.
final class ReferralEvidenceStoreTests: XCTestCase {

    private let suite = "ReferralEvidenceStoreTests"

    private func makeStore() -> ReferralEvidenceStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ReferralEvidenceStore(defaults: defaults)
    }

    func testClearTokenDropsTheTokenAndKeepsTheInstall() {
        let store = makeStore()
        store.remember(installId: "install-1")
        store.remember(token: "t", expiresAt: nil)

        store.clearToken(ifHolding: "t")

        XCTAssertNil(store.evidence.recoveryToken)
        XCTAssertEqual(store.evidence.installId, "install-1")
    }

    func testClearTokenLeavesANewerTokenAlone() {
        let store = makeStore()
        store.remember(token: "newer", expiresAt: nil)

        store.clearToken(ifHolding: "older")

        XCTAssertEqual(store.evidence.recoveryToken, "newer")
    }

    func testClearTokenNeverLosesAConcurrentWrite() {
        for round in 0..<300 {
            let store = makeStore()
            store.remember(token: "t", expiresAt: nil)

            DispatchQueue.concurrentPerform(iterations: 2) { index in
                if index == 0 {
                    store.remember(installId: "install-\(round)")
                } else {
                    store.clearToken(ifHolding: "t")
                }
            }

            XCTAssertEqual(store.evidence.installId, "install-\(round)", "round \(round) lost the install id")
            XCTAssertNil(store.evidence.recoveryToken)
        }
    }
}
