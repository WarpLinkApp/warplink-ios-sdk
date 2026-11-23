import Foundation

/// What a Tether read depends on and what it leaves behind, in one place so a
/// test can replace the clipboard and the read queue. Restored by
/// `WarpLink.reset()`.
enum TetherServices {

    typealias Miss = (reason: TetherMissReason, mode: TetherReadMode)

    private static let lock = NSLock()
    private static var storedMiss: Miss?
    private static var storedReceipt: String?
    private static var storedPlatform = defaultPlatform

    static let defaultPlatform = "ios"
    private static let wrappers: Set<String> = ["react-native", "flutter"]

    static var clipboard: TetherClipboard = makeSystemClipboard()

    /// Runs a clipboard read. Off the main thread, because a read may wait on
    /// the system paste prompt.
    static var readQueue: (@escaping () -> Void) -> Void = { work in
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    /// The reason the last read found no code, until a request carries it.
    static func recordMiss(_ reason: TetherMissReason, mode: TetherReadMode) {
        lock.lock(); defer { lock.unlock() }
        storedMiss = (reason, mode)
    }

    /// Hands the kept miss to one request and forgets it.
    static func takeMiss() -> Miss? {
        lock.lock(); defer { lock.unlock() }
        defer { storedMiss = nil }
        return storedMiss
    }

    /// The `sdk_platform` a match request reports: `ios`, or the cross-platform
    /// SDK a bridge declared.
    static var sdkPlatform: String {
        lock.lock(); defer { lock.unlock() }
        return storedPlatform
    }

    /// Records the hosting SDK. A name that is not a known wrapper is ignored.
    static func declareWrapper(_ name: String) {
        guard wrappers.contains(name) else { return }
        lock.lock(); defer { lock.unlock() }
        storedPlatform = name
    }

    static var testReceipt: String? {
        lock.lock(); defer { lock.unlock() }
        return storedReceipt
    }

    static func recordTestReceipt(_ receipt: String?) {
        lock.lock(); defer { lock.unlock() }
        storedReceipt = receipt
    }

    /// Forgets the kept miss and receipt. Called with `clearAttribution()`.
    static func clearAll() {
        lock.lock(); defer { lock.unlock() }
        storedMiss = nil
        storedReceipt = nil
    }

    static func reset() {
        clearAll()
        lock.lock()
        storedPlatform = defaultPlatform
        lock.unlock()
        clipboard = makeSystemClipboard()
        readQueue = { work in DispatchQueue.global(qos: .userInitiated).async(execute: work) }
    }
}
