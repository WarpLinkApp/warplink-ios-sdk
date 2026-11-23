import Foundation

/// The installation id: one random UUID per install, sent on every attribution
/// match so the server can tell this install from another.
///
/// It lives in the install marker store, which is excluded from backups and
/// deleted with the app, so a reinstall or a restore to a new device makes a
/// new id. If the store cannot write, the id lasts for this process only.
final class InstallationIdStore {

    private let store: InstallMarkerStore
    private let key: String
    private let lock = NSLock()
    private var cached: String?

    init(store: InstallMarkerStore, key: String) {
        self.store = store
        self.key = key
    }

    /// The id of this install, made on first use.
    var id: String {
        lock.lock(); defer { lock.unlock() }
        if let cached = cached { return cached }
        let stored = store.value(key).flatMap { UUID(uuidString: $0) }?.uuidString.lowercased()
        let id = stored ?? UUID().uuidString.lowercased()
        if stored == nil {
            store.write(key, value: id)
        }
        cached = id
        return id
    }

    /// Forgets the id, so the next one is new.
    @discardableResult
    func clear() -> Bool {
        lock.lock(); defer { lock.unlock() }
        cached = nil
        return store.clear(key)
    }
}
