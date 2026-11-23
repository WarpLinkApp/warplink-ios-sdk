import Foundation
@testable import WarpLink

// MARK: - Shared test helpers

enum TestSupport {
    /// Options that disable all auto behavior — used by tests that exercise the
    /// SDK's manual paths and must not fire background network/attribution work.
    static var noAuto: WarpLinkOptions {
        WarpLinkOptions(autoDeepLinkHandling: false, autoDeferredCheck: false)
    }
}

/// In-memory marker store, so tests touch neither the real Keychain nor the
/// host's Application Support directory.
///
/// Serves both roles: which contract an instance stands in for is decided by the
/// `Storage` slot it is injected into, and a reinstall is simulated by keeping
/// the durable instance while replacing the install one.
final class InMemoryMarkerStore: DurableMarkerStore, InstallMarkerStore {
    private var marks = Set<String>()
    private var values = [String: String]()

    @discardableResult
    func mark(_ key: String) -> Bool {
        marks.insert(key)
        return true
    }

    func isMarked(_ key: String) -> Bool {
        marks.contains(key) || values[key] != nil
    }

    @discardableResult
    func clear(_ key: String) -> Bool {
        marks.remove(key)
        values[key] = nil
        return true
    }

    func value(_ key: String) -> String? { values[key] }

    @discardableResult
    func write(_ key: String, value: String) -> Bool {
        values[key] = value
        return true
    }
}

/// A marker store that can never write, simulating a host where the underlying
/// store is unusable (unsigned test host, missing entitlement, read-only
/// container).
final class FailingMarkerStore: DurableMarkerStore, InstallMarkerStore {
    @discardableResult
    func mark(_ key: String) -> Bool { false }

    func isMarked(_ key: String) -> Bool { false }

    @discardableResult
    func clear(_ key: String) -> Bool { false }

    func value(_ key: String) -> String? { nil }

    @discardableResult
    func write(_ key: String, value: String) -> Bool { false }
}

extension URLRequest {
    /// The request's POST body, read from the stream when needed.
    ///
    /// `URLSession` hands a `URLProtocol` subclass the request with `httpBody`
    /// set to `nil` and the payload moved to `httpBodyStream`. Reading
    /// `httpBody` alone therefore yields nothing, which silently turns any
    /// wire-body assertion in a mock into a no-op.
    var resolvedHTTPBody: Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }

        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var data = Data()
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// A mutable reference box for capturing values inside `@Sendable` callbacks.
final class Box<T> {
    var value: T?
    init() {}
}

/// The requests a transport was handed, in order, behind a lock.
///
/// Shared by every transport double: "how many requests did that make, and what
/// did they carry?" is the question a retry test asks, and each double answering
/// it with its own array and its own lock is how two of them came to disagree
/// about whether `/sdk/validate` counted.
final class SentRequestLog {

    private let lock = NSLock()
    private var sent: [URLRequest] = []

    func record(_ request: URLRequest) {
        lock.lock(); sent.append(request); lock.unlock()
    }

    /// Every request, in order.
    var all: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return sent
    }

    func matching(pathContaining fragment: String) -> [URLRequest] {
        all.filter { $0.url?.path.contains(fragment) == true }
    }

    func count(forPathContaining fragment: String) -> Int {
        matching(pathContaining: fragment).count
    }

    /// The tap id each matching request carried, in order. Nil for a request
    /// that carried none.
    func tapIds(forPathContaining fragment: String) -> [String?] {
        matching(pathContaining: fragment).map {
            $0.value(forHTTPHeaderField: APIClient.tapIdHeader)
        }
    }
}
