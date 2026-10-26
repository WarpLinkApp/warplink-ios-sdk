import Foundation
#if canImport(Security)
import Security
#endif

/// `ReferralPendingStore` backed by one Keychain item.
///
/// The Keychain keeps the token out of the app's plain files, and the
/// this-device-only class keeps it from being restored onto another device.
/// Its items outlive an app delete, which this record must not: a token left
/// from an earlier install would be redeemed for the next one. So the record is
/// honoured only while an install-scoped marker exists, and that marker lives
/// in a store the system removes with the app.
final class KeychainPendingStore: ReferralPendingStore {

    private static let account = "referral_pending_redemption"
    private static let installMarker = "referral_pending_redemption"
    #if canImport(Security)
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    #endif

    private let service: String
    private let installMarkers: InstallMarkerStore

    init(
        service: String = "app.warplink.sdk.\(Bundle.main.bundleIdentifier ?? "unknown")",
        installMarkers: InstallMarkerStore = BackupExcludedFileStore()
    ) {
        self.service = service
        self.installMarkers = installMarkers
    }

    func load() -> PendingRedemption? {
        guard installMarkers.isMarked(Self.installMarker) else {
            remove()
            return nil
        }
        guard let data = read() else { return nil }
        guard let record = try? JSONDecoder().decode(PendingRedemption.self, from: data) else {
            clear()
            return nil
        }
        return record
    }

    @discardableResult
    func save(_ record: PendingRedemption) -> Bool {
        guard let data = try? JSONEncoder().encode(record) else { return false }
        guard write(data), installMarkers.mark(Self.installMarker) else { return false }
        return true
    }

    func clear() {
        remove()
        installMarkers.clear(Self.installMarker)
    }

    // MARK: - Keychain

    private var identity: [String: Any] {
        var query: [String: Any] = [:]
        #if canImport(Security)
        query[kSecClass as String] = kSecClassGenericPassword
        query[kSecAttrService as String] = service
        query[kSecAttrAccount as String] = Self.account
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    private func read() -> Data? {
        #if canImport(Security)
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
        #else
        return nil
        #endif
    }

    private func write(_ data: Data) -> Bool {
        #if canImport(Security)
        let update = SecItemUpdate(
            identity as CFDictionary,
            [kSecValueData as String: data, kSecAttrAccessible as String: Self.accessibility] as CFDictionary
        )
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var add = identity
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = Self.accessibility
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        #else
        return false
        #endif
    }

    private func remove() {
        #if canImport(Security)
        SecItemDelete(identity as CFDictionary)
        #endif
    }
}
