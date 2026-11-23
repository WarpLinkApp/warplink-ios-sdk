import Foundation

/// What an attribution answer means: which result the caller gets, and what the
/// SDK keeps. `WarpLink+AttributionMatch.swift` asks the server.
extension WarpLink {

    /// What the whole run, retries included, amounted to.
    static func applyAttributionResult(
        _ result: Result<AttributionResponse, WarpLinkError>,
        store: Storage,
        log: Logger?,
        generation: Int,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        switch result {
        case let .failure(error):
            deliverAttributionFailure(
                error, store: store, log: log, generation: generation, completion: completion
            )
        case let .success(response):
            handleAttributionResponse(
                response, store: store, log: log,
                generation: generation, completion: completion
            )
        }
    }

    /// Keeps a decoded 200 answer the moment it is read, on the network queue,
    /// before the hop to the main queue that hands it to the app. Without this a
    /// process that ends in that gap leaves the gate open, and a later check
    /// asks again for an install the server has already answered.
    ///
    /// An answer that will not stand is left alone: a test code is sent again
    /// without the code (see `settleTether`), so its answer is not this install's.
    /// `handleAttributionResponse` applies the same answer again when it
    /// reaches the main queue, which changes nothing.
    static func applyDecodedAnswer(
        _ response: AttributionResponse,
        sent: TetherRequestFields,
        store: Storage,
        generation: Int
    ) {
        if sent.code != nil, response.tether?.test == true { return }
        let matched = deferredLink(from: response)
        _ = applyIfCurrent(
            matched, definitive: isDefinitive(response, routed: matched),
            installId: response.installId, store: store, generation: generation
        )
    }

    /// The run failed, every attempt spent. THE GATE STAYS OPEN.
    ///
    /// Nothing here calls `markAttributionComplete`, and nothing may: three
    /// failed attempts are still "did not complete", so a later check tries
    /// again, once the wait the failure counted when the request was sent has
    /// passed (`CountedCheck`). Closing the gate on a retry-exhausted failure would
    /// cost a user who happened to be offline at launch their attribution for good.
    private static func deliverAttributionFailure(
        _ error: WarpLinkError,
        store: Storage,
        log: Logger?,
        generation: Int,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        // An abandoned check answers with the no-op success, exactly as its
        // response path does. A reconfigure CANCELS the request it abandons, and
        // that surfaces as `.networkError(URLError(.cancelled))`; routing it on
        // would push an error into `onLink` for a reconfigure the app asked for.
        // It is no failure of the network either: `settle()` gave back its count.
        guard endCountedCheckIfCurrent(generation: generation) else {
            log?.log("Deferred check abandoned by reconfigure, discarding its failure")
            completion(.success(nil))
            return
        }
        log?.log("Attribution match failed (will retry later): \(error.localizedDescription)")
        completion(.failure(error))
    }

    private static func handleAttributionResponse(
        _ response: AttributionResponse,
        store: Storage,
        log: Logger?,
        generation: Int,
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        let matched = deferredLink(from: response)
        let definitive = isDefinitive(response, routed: matched)

        // A check abandoned by a reconfigure answers with the `.success(nil)`
        // no-op, never a fabricated `.notConfigured`: the SDK is configured, and
        // the auto path routes this completion straight to the host's `onLink`,
        // where an invented error would be a misleading thing to show a user.
        // `dispatchToOnLink` already swallows `.success(nil)`, so an abandoned
        // auto check is silent (parity with Android).
        guard applyIfCurrent(
            matched, definitive: definitive, installId: response.installId,
            store: store, generation: generation
        ) else {
            log?.log("Deferred check abandoned by reconfigure, discarding its result")
            completion(.success(nil))
            return
        }

        log?.log(resultLog(matched: matched, definitive: definitive))
        completion(.success(matched))
    }

    /// Whether this response settles attribution for the install.
    ///
    /// A pending Tether answer never does: the code is on its way, so the next
    /// launch asks again. A confirmed no-match does: the server looked, found
    /// nothing, and the check has done its job. A `matched` response the SDK
    /// cannot route does NOT, whatever the server called it. It names no link
    /// and carries no destination, so `deferredLink(from:)` throws it away and
    /// the host is told nothing matched. Closing the gate on that spends the
    /// install's one check on an answer nobody can act on, and nothing ever
    /// retries: the gate outlives every relaunch, and only a reinstall clears it.
    private static func isDefinitive(
        _ response: AttributionResponse, routed: WarpLinkDeepLink?
    ) -> Bool {
        guard response.tether?.isPending != true else { return false }
        return !response.matched || routed != nil
    }

    private static func resultLog(
        matched: WarpLinkDeepLink?, definitive: Bool
    ) -> String {
        if let matched = matched {
            return "Deferred deep link matched: \(matched.linkId)"
        }
        return definitive
            ? "No deferred deep link match"
            : "Attribution matched with nothing to route to, will retry on a later check"
    }

    /// Persist a definitive response, but only while `generation` is still the
    /// live check; returns false for an abandoned one, which applies nothing.
    ///
    /// A response that is not `definitive` also writes nothing, and returns
    /// true: this IS the live check, it simply has nothing worth keeping and
    /// must leave the gate open for the next launch. The failure the check
    /// counted when it sent stays, so that launch waits.
    ///
    /// The generation test and the writes, install id included, share a single
    /// lock hold: a `configure()` or `clearAttribution()` landing between them
    /// would let a stale answer mark attribution complete, blank the match the
    /// successor cached, or restore an install id that was just cleared.
    ///
    /// Safe to call twice for one answer: the second call finds the gate closed
    /// and writes the same link again.
    private static func applyIfCurrent(
        _ deepLink: WarpLinkDeepLink?,
        definitive: Bool,
        installId: String?,
        store: Storage,
        generation: Int
    ) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard generation == deferredCheckGeneration else { return false }
        ReferralServices.evidenceStore.remember(installId: installId)
        // The check has its answer, so it is no longer open to a give-back.
        countedCheck = nil
        guard definitive else { return true }
        if !store.isAttributionComplete { store.markAttributionComplete() }
        store.cachedAttribution = deepLink
        if let link = deepLink, onLinkRoutedGeneration == generation, options?.onLink != nil {
            store.markAwaitingDelivery(link.routeIdentity)
        }
        store.clearCheckBackoff()
        return true
    }

    private static func deferredLink(from response: AttributionResponse) -> WarpLinkDeepLink? {
        ReferralMatch.deepLink(from: response)
    }
}
