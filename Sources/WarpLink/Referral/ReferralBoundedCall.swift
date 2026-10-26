import Foundation

/// One referral request, run under the same bounds as the attribution match:
/// each attempt is capped in wall time, and a transient failure is retried
/// within the shared attempt count and total budget.
enum ReferralBoundedCall {

    /// - Parameter send: issues one attempt with that attempt's timeout and
    ///   answers through the closure it is given.
    static func run<T>(
        client: APIClient,
        send: @escaping (TimeInterval, @escaping (Result<T, WarpLinkError>) -> Void) -> HTTPTask,
        completion: @escaping (Result<T, WarpLinkError>) -> Void
    ) {
        BoundedRetry.run(
            isCurrent: { true },
            attempt: { number, done in
                let timeout = RetryPolicy.timeout(forAttempt: number)
                _ = AttemptWatchdog.bound(
                    timeout: timeout,
                    completion: done,
                    discardConnection: { client.transport.discardConnections() }
                ) { answer in
                    send(timeout, answer)
                }
            },
            completion: completion
        )
    }
}
