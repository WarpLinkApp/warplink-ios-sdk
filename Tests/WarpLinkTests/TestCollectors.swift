import Foundation
@testable import WarpLink

// MARK: - Thread-safe recorders for transport and callback tests

/// A thread-safe log of an optional wire flag, one entry per request served.
///
/// Holds `Bool?` rather than `Bool` so a test can tell "sent as false" apart
/// from "not sent at all", which are different facts to the attribution server.
final class ReportedFlags {
    private let lock = NSLock()
    private var values: [Bool?] = []

    func append(_ value: Bool?) {
        lock.lock(); values.append(value); lock.unlock()
    }

    var all: [Bool?] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}

/// A thread-safe counter for asserting how many times a callback fired.
final class Counter {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock(); count += 1; lock.unlock()
    }

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
}

/// Every result `onLink` was handed, in order, behind a lock.
final class Results {
    private let lock = NSLock()
    private var recorded: [Result<WarpLinkDeepLink?, WarpLinkError>] = []

    var all: [Result<WarpLinkDeepLink?, WarpLinkError>] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func append(_ result: Result<WarpLinkDeepLink?, WarpLinkError>) {
        lock.lock(); recorded.append(result); lock.unlock()
    }
}

/// A one-way flag a `@Sendable` transport closure can raise.
final class Flag {
    private let lock = NSLock()
    private var raised = false

    var isRaised: Bool {
        lock.lock(); defer { lock.unlock() }
        return raised
    }

    func raise() {
        lock.lock(); raised = true; lock.unlock()
    }
}

/// A countdown a transport closure spends, one answer at a time.
final class Budget {
    private let lock = NSLock()
    private var remaining: Int

    init(_ remaining: Int) {
        self.remaining = remaining
    }

    /// True while there was something left to spend.
    func spend() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard remaining > 0 else { return false }
        remaining -= 1
        return true
    }
}
