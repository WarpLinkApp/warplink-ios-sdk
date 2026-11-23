import Foundation

extension WarpLink {

    /// One bounded attempt of the attribution match request.
    ///
    /// Every attempt is bounded, the first included, and bounded in wall time
    /// rather than only between bytes. Same watchdog as the resolve path, for
    /// the reasons stated there, and the same fresh connection after a timeout
    /// or an OS-cancelled attempt.
    static func attemptAttributionMatch(
        number: Int,
        request: DeferredCheckRequest,
        client: APIClient,
        store: Storage,
        tapId: String,
        generation: Int,
        done: @escaping (Result<AttributionResponse, WarpLinkError>) -> Void
    ) {
        let timeout = RetryPolicy.timeout(forAttempt: number)
        let task = AttemptWatchdog.boundClaiming(
            timeout: timeout,
            completion: done,
            discardConnection: { client.transport.discardConnections() }
        ) { answer, claimAnswer in
            client.matchAttribution(
                signals: request.signals, sdkVersion: sdkVersion,
                deviceId: request.deviceId, isReinstall: request.isReinstall,
                tapId: tapId, tether: request.tether, attemptNumber: request.attemptNumber,
                timeout: timeout,
                onDecoded: { response in
                    // On the network queue, before the hop to the main queue
                    // that hands the answer on: a process that ends in between
                    // must not leave the gate open for an answer already given.
                    store.savePolicy(response.sdkPolicy)
                    guard claimAnswer() else { return }
                    applyDecodedAnswer(
                        response, sent: request.tether, store: store, generation: generation
                    )
                },
                completion: answer
            )
        }
        // Recorded so a reconfigure can stop this attempt rather than merely
        // ignore its answer.
        setInFlightDeferredCheck(task, generation: generation)
    }
}
