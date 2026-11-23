import Foundation

/// A failure and an attempt number that a check put on the books when it sent
/// its request.
///
/// A check counts as failed from the moment it is sent, so a process that ends
/// while the request is out, or while a Tether answer is pending, leaves the
/// failure behind and the next launch waits. A 200 that closes the gate clears
/// it. A check that `configure()` abandons gives both back.
struct CountedCheck {
    let store: Storage
    let before: CheckBackoff?
    let attemptNumberBefore: Int
    /// The number this check sends. It is taken with the failure, under the same lock.
    let attemptNumber: Int
    private let backoffAfter: CheckBackoff?

    /// Records the failure and takes the attempt number, and keeps what they replaced.
    static func count(on store: Storage, at time: Date) -> CountedCheck {
        let before = store.checkBackoff
        let attemptNumberBefore = store.attemptNumber
        store.recordCheckFailure(at: time)
        let number = store.takeAttemptNumber()
        return CountedCheck(
            store: store, before: before, attemptNumberBefore: attemptNumberBefore,
            attemptNumber: number, backoffAfter: store.checkBackoff
        )
    }

    /// Gives both back, unless something else has changed them since this check
    /// wrote them: a newer check's failure and number stay.
    ///
    /// The compare and the restore share one `WarpLink.lock` hold, so a newer
    /// check cannot write between them and lose its failure. Call outside the
    /// lock: `NSLock` is not recursive.
    func giveBack() {
        WarpLink.lock.lock(); defer { WarpLink.lock.unlock() }
        guard store.checkBackoff == backoffAfter, store.attemptNumber == attemptNumber else { return }
        store.restoreCheckBackoff(before)
        store.restoreAttemptNumber(attemptNumberBefore)
    }
}

extension WarpLink {

    /// Counts the check about to send, unless `generation` was abandoned.
    /// Nil when it was: nothing is recorded.
    static func beginCountedCheck(store: Storage, generation: Int) -> CountedCheck? {
        lock.lock(); defer { lock.unlock() }
        guard generation == deferredCheckGeneration else { return nil }
        let counted = CountedCheck.count(on: store, at: SDKEnvironment.now())
        countedCheck = counted
        return counted
    }

    /// The check has its answer. The failure it counted stays on the books.
    /// The generation test and the clear share one lock hold. False when
    /// `generation` was abandoned: nothing is cleared.
    static func endCountedCheckIfCurrent(generation: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard generation == deferredCheckGeneration else { return false }
        countedCheck = nil
        return true
    }
}
