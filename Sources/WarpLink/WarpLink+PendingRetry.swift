import Foundation

/// The one retry of a pending Tether answer on the deferred check.
extension WarpLink {

    /// Waits, then sends the same request once more. If the app was backgrounded
    /// and that retry fails or never runs, the next time the app becomes active
    /// starts one more check (see `PendingForegroundRetry`).
    static func retryPendingMatch(
        after wait: TimeInterval,
        first: Result<AttributionResponse, WarpLinkError>,
        request: DeferredCheckRequest,
        client: APIClient,
        store: Storage,
        log: Logger?,
        generation: Int,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        PendingForegroundRetry.arm()
        SDKEnvironment.schedule(wait) {
            guard isCurrentDeferredCheck(generation) else {
                applyAttributionResult(
                    first, store: store, log: log,
                    generation: generation, completion: completion
                )
                return
            }
            performAttributionMatch(
                request: request, client: client, store: store, log: log,
                generation: generation, pendingRetried: true, completion: completion
            )
        }
    }

    /// The wait before the one retry, when the answer is a pending Tether code.
    static func pendingWait(_ result: Result<AttributionResponse, WarpLinkError>) -> TimeInterval? {
        guard case let .success(response) = result else { return nil }
        return TetherPending.wait(for: response.tether)
    }
}

extension WarpLink {
    static var isCheckInFlight: Bool {
        lock.lock(); defer { lock.unlock() }
        return deferredCheckInFlight
    }

    /// What the pending recheck does on this activation, from the same gate the
    /// check itself obeys.
    static func pendingRecheckVerdict() -> PendingForegroundRetry.Verdict {
        guard let deps = DeferredCheckDeps.current(), !deps.store.isAttributionComplete else {
            return .done
        }
        let reading = readCheckGate(store: deps.store, environment: deps.environment)
        switch reading.gate {
        case .send: return .run
        case .skip(.retryWait): return .wait
        case .skip(.installTooOld), .skip(.gaveUp):
            recordCheckGate(reading, store: deps.store, log: deps.log)
            return .done
        }
    }
}

/// One check when the app next becomes active after a pending answer.
///
/// A wait scheduled before the app went to the background may fail or not run.
/// The gate is still open then, so this asks again, once. It does nothing when
/// attribution is complete or a check is already running. It stays armed while
/// a failure is being waited out, so the recheck is not spent on a skip.
enum PendingForegroundRetry {

    /// The system's "app became active" notification, named by its raw value so
    /// no UI framework is needed here.
    static var notificationName = Notification.Name(
        {
            #if canImport(AppKit) && !canImport(UIKit)
            return "NSApplicationDidBecomeActiveNotification"
            #else
            return "UIApplicationDidBecomeActiveNotification"
            #endif
        }()
    )

    private static var observer: NSObjectProtocol?

    /// Arms the one-shot. A second call while armed changes nothing.
    static func arm() {
        WarpLink.lock.lock(); defer { WarpLink.lock.unlock() }
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: notificationName, object: nil, queue: nil
        ) { _ in
            // A running check may still fail, so stay armed until one starts
            // here or attribution is complete.
            guard !WarpLink.isCheckInFlight else { return }
            switch WarpLink.pendingRecheckVerdict() {
            case .wait:
                return
            case .done:
                disarm()
            case .run:
                disarm()
                WarpLink.runAutoDeferredCheck()
            }
        }
    }

    enum Verdict: Equatable {
        /// A failure is being waited out: keep listening.
        case wait
        /// Nothing more can be sent: stop listening.
        case done
        case run
    }

    static func disarm() {
        WarpLink.lock.lock(); defer { WarpLink.lock.unlock() }
        if let held = observer { NotificationCenter.default.removeObserver(held) }
        observer = nil
    }
}
