import Foundation
#if canImport(Security)
import Security
#endif

/// A small durable boolean-marker store.
///
/// Contract: a marker written here MUST survive app deletion and MUST come back
/// from an iCloud/iTunes restore. It is the opposite of `InstallMarkerStore`.
///
/// It records only that this device has been attributed for this app at some
/// point, which is what tells a reinstall apart from a first install. It gates
/// nothing: a device-lifetime marker that gates the deferred check is exactly
/// why iOS used to skip attribution on every reinstall.
protocol DurableMarkerStore {
    @discardableResult func mark(_ key: String) -> Bool
    func isMarked(_ key: String) -> Bool
    @discardableResult func clear(_ key: String) -> Bool
}

/// Keychain-backed `DurableMarkerStore` using `Security.framework`.
///
/// The Keychain is the only iOS store that meets the durable contract: its
/// items outlive an app delete, and an item that is not `...ThisDeviceOnly` is
/// carried into an encrypted backup and restored onto a replacement device.
///
/// Uses the data-protection keychain (`kSecUseDataProtectionKeychain`) so
/// operations never present an interactive prompt; failures (e.g. missing
/// entitlement in an unsigned test host) degrade gracefully to "not marked".
///
/// The default service is scoped to the host bundle identifier so sibling apps
/// sharing a keychain access group never read each other's markers.
final class KeychainStore: DurableMarkerStore {

    private let service: String

    init(service: String = "app.warplink.sdk.\(Bundle.main.bundleIdentifier ?? "unknown")") {
        self.service = service
    }

    @discardableResult
    func mark(_ key: String) -> Bool {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data([1]),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        // An item that is already there is a success, not a reason to delete
        // first. A delete-then-add that failed on the add erased a correct
        // marker that nothing can rebuild, and the next reinstall then read as a
        // first install.
        return status == errSecSuccess || status == errSecDuplicateItem
        #else
        return false
        #endif
    }

    func isMarked(_ key: String) -> Bool {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
        #else
        return false
        #endif
    }

    @discardableResult
    func clear(_ key: String) -> Bool {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
        #else
        return false
        #endif
    }
}
