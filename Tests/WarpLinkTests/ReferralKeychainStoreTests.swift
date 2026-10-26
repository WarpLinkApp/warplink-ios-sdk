import XCTest
import Security
@testable import WarpLink

/// The Keychain-backed record of a pasted invitation waiting for a retry.
/// The install marker store is in memory, and the service name is unique to the
/// test, so nothing here touches the host app's real items.
final class ReferralKeychainStoreTests: XCTestCase {

    private var markers: InMemoryMarkerStore!
    private var store: KeychainPendingStore!
    private let record = PendingRedemption(
        token: "t", expiresAt: Date(timeIntervalSince1970: 1_900_000_000), attempts: 2
    )

    override func setUp() {
        super.setUp()
        markers = InMemoryMarkerStore()
        store = KeychainPendingStore(
            service: "app.warplink.sdk.tests.\(UUID().uuidString)", installMarkers: markers
        )
    }

    override func tearDown() {
        store.clear()
        super.tearDown()
    }

    private func saveOrSkip() throws {
        guard store.save(record) else { throw XCTSkip("The Keychain is not available to this test run.") }
    }

    func testARecordRoundTrips() throws {
        try saveOrSkip()

        XCTAssertEqual(store.load()?.token, "t")
        XCTAssertEqual(store.load()?.attempts, 2)
    }

    func testTheItemStaysOnThisDevice() throws {
        let service = "app.warplink.sdk.tests.\(UUID().uuidString)"
        let own = KeychainPendingStore(service: service, installMarkers: markers)
        defer { own.clear() }
        guard own.save(record) else { throw XCTSkip("The Keychain is not available to this test run.") }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "referral_pending_redemption",
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnAttributes as String: true,
        ]
        var item: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &item), errSecSuccess)
        let attributes = try XCTUnwrap(item as? [String: Any])
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
    }

    func testARecordFromAnEarlierInstallIsNotHonoured() throws {
        try saveOrSkip()
        // A deleted app takes the install marker with it. The Keychain item stays.
        markers.clear("referral_pending_redemption")

        XCTAssertNil(store.load(), "an old install's token must never be redeemed for this one")
        XCTAssertNil(store.load(), "and it is removed, not just ignored")
    }

    func testClearRemovesTheRecord() throws {
        try saveOrSkip()

        store.clear()

        XCTAssertNil(store.load())
    }

    func testARecordIsSpentAfterTheLastAttempt() {
        XCTAssertTrue(record.hasAttemptsLeft)
        let spent = PendingRedemption(token: "t", expiresAt: record.expiresAt, attempts: PendingRedemption.maxAttempts)
        XCTAssertFalse(spent.hasAttemptsLeft)
    }

    func testARecordIsExpiredAtItsExpiry() {
        XCTAssertFalse(record.isExpired(at: Date(timeIntervalSince1970: 1_899_999_999)))
        XCTAssertTrue(record.isExpired(at: Date(timeIntervalSince1970: 1_900_000_000)))
    }
}
