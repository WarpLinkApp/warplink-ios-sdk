import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Runs work only while the app is in the foreground.
enum AppForeground {

    enum Disposition: Equatable {
        case runNow
        case waitForActivation
    }

    /// Whether to wait for the app to become active.
    ///
    /// Without an app object, or inside an app extension, there is no foreground
    /// to wait for. A process under XCTest that is not active is the same: a
    /// customer test would otherwise wait for an activation that never comes.
    static func disposition(
        hasApplication: Bool, isExtension: Bool, isActive: Bool, underTests: Bool
    ) -> Disposition {
        if !hasApplication || isExtension || isActive || underTests { return .runNow }
        return .waitForActivation
    }

    #if canImport(UIKit)
    /// Runs `work` now when the app is active, and otherwise once, at the next
    /// activation. `work` runs on the main queue, except where there is no app
    /// to wait for, where it runs at once.
    static func whenActive(_ work: @escaping () -> Void) {
        // `UIApplication.shared` cannot be named here: it is unavailable to app
        // extensions, and the SDK must build for them. Looked up at runtime.
        let application = UIApplication.value(forKey: "sharedApplication") as? UIApplication
        let isExtension = Bundle.main.bundlePath.hasSuffix(".appex")
        guard let application = application, !isExtension else { work(); return }
        // `applicationState` may only be read on the main queue.
        DispatchQueue.main.async {
            let action = disposition(
                hasApplication: true, isExtension: false,
                isActive: application.applicationState == .active,
                underTests: NSClassFromString("XCTestCase") != nil
            )
            switch action {
            case .runNow: work()
            case .waitForActivation: ActivationWaiter(work).start()
            }
        }
    }
    #else
    /// Without UIKit there is no foreground to wait for.
    static func whenActive(_ work: @escaping () -> Void) {
        work()
    }
    #endif
}

#if canImport(UIKit)
/// Waits for one `didBecomeActive` notification, runs its work, and stops
/// listening. It holds itself alive through the observer until then.
private final class ActivationWaiter {

    private let lock = NSLock()
    private var token: NSObjectProtocol?
    private let work: () -> Void

    init(_ work: @escaping () -> Void) {
        self.work = work
    }

    func start() {
        let observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
        ) { [self] _ in fire() }
        lock.lock(); token = observer; lock.unlock()
    }

    private func fire() {
        lock.lock()
        let observer = token
        token = nil
        lock.unlock()
        guard let observer = observer else { return }
        NotificationCenter.default.removeObserver(observer)
        work()
    }
}
#endif
