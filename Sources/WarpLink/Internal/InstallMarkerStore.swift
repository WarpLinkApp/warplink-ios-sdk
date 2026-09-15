import Foundation

/// A per-install boolean-marker store.
///
/// Contract: a marker written here must NOT survive app deletion, and must NOT
/// come back from an iCloud/iTunes restore. Anything that can come back would
/// gate a genuinely new install and silently lose its attribution.
///
/// Deliberately a different type from `DurableMarkerStore`, which has the
/// opposite contract (survives both). One store serving both jobs is what made
/// iOS skip attribution after every reinstall, so the two roles are kept apart
/// in the type system: a call site cannot swap one for the other by accident.
protocol InstallMarkerStore {
    @discardableResult func mark(_ key: String) -> Bool
    func isMarked(_ key: String) -> Bool
    @discardableResult func clear(_ key: String) -> Bool
}

/// File-backed `InstallMarkerStore` that keeps its markers out of backups.
///
/// Why not `UserDefaults`: the app's preferences are included in iCloud/iTunes
/// backups, so a restored device would arrive with the gate already closed and
/// would never attribute the install it just performed.
///
/// Why `Application Support` and not `Library/Caches`: Caches is already
/// excluded from backups, but the system may purge it at any time. A purged gate
/// reads as "not marked" and re-fires attribution in the middle of one install,
/// which is the duplicate this store exists to prevent. Application Support is
/// never purged, so the SDK creates its own subdirectory there and excludes only
/// that subdirectory. Excluding Application Support itself would drop the host
/// app's own data out of every backup.
final class BackupExcludedFileStore: InstallMarkerStore {

    /// Reverse-DNS so the SDK never collides with a host app that keeps its own
    /// files in the shared Application Support directory.
    private static let directoryName = "app.warplink.sdk"

    private let fileManager: FileManager
    private let directory: URL?

    /// - Parameter directory: overridden by tests so they write to a temporary
    ///   location instead of the host's real Application Support directory.
    init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
    }

    @discardableResult
    func mark(_ key: String) -> Bool {
        guard let directory = directory, prepareDirectory(directory) else { return false }
        return fileManager.createFile(
            atPath: directory.appendingPathComponent(key).path,
            contents: Data([1]),
            attributes: Self.writeAttributes
        )
    }

    func isMarked(_ key: String) -> Bool {
        guard let directory = directory else { return false }
        return fileManager.fileExists(atPath: directory.appendingPathComponent(key).path)
    }

    @discardableResult
    func clear(_ key: String) -> Bool {
        guard let directory = directory else { return false }
        let path = directory.appendingPathComponent(key).path
        guard fileManager.fileExists(atPath: path) else { return true }
        do {
            try fileManager.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private

    private static func defaultDirectory(fileManager: FileManager) -> URL? {
        fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Create the directory if needed and (re-)assert the backup exclusion.
    ///
    /// The exclusion is re-applied on every write rather than only at creation:
    /// the directory may already exist from a build that did not set the flag,
    /// and an unexcluded gate is worse than no gate at all.
    ///
    /// A failure degrades to `false` instead of throwing. A marker store that
    /// cannot write must never break attribution for the host app; `Storage`
    /// answers a `false` here with its own per-install fallback.
    private func prepareDirectory(_ directory: URL) -> Bool {
        do {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            var url = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }

    /// The gate is written on a definitive response, which can arrive in the
    /// background before the device has ever been unlocked. The stricter
    /// protection classes make the file unwritable there, and a failed write
    /// sends `Storage` to its UserDefaults fallback, which a restore carries. So
    /// the class is pinned to the most permissive one that still encrypts at
    /// rest. Reads are unaffected either way: `isMarked` only stats the path.
    private static var writeAttributes: [FileAttributeKey: Any] {
        #if canImport(UIKit)
        return [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        return [:]
        #endif
    }
}
