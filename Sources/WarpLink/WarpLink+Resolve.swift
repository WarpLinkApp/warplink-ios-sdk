import Foundation

extension WarpLink {

    /// Resolve an incoming Universal Link URL to a deep link (manual/advanced).
    ///
    /// Most apps don't need this: with `autoDeepLinkHandling` on (default),
    /// deliver links via `WarpLink.continue(_:)` / `WarpLink.open(_:)` and read
    /// results from `onLink`. Use this when you want the result inline.
    public static func handleDeepLink(
        _ url: URL,
        completion: @escaping (Result<WarpLinkDeepLink, WarpLinkError>) -> Void
    ) {
        performResolve(url, completion: completion)
    }

    /// Deliver a `URL` to the SDK (host one-liner, e.g. SwiftUI `.onOpenURL`).
    ///
    /// Resolves the link and routes the result to `onLink`. Returns `true` if
    /// the URL was a WarpLink link the SDK will handle. No-op (returns `false`)
    /// when `autoDeepLinkHandling` is disabled.
    @discardableResult
    public static func open(_ url: URL) -> Bool {
        guard isConfigured else { return false }
        lock.lock(); let auto = options?.autoDeepLinkHandling ?? true; lock.unlock()
        guard auto else { return false }
        guard isWarpLinkURL(url) else { return false }
        if shouldSuppressDuplicate(url) { return true }

        // Bumps the generation and stops whatever the previous tap still has on
        // the wire. Ignoring the older attempt is not enough: its connection
        // would stay open for the whole of its timeout.
        let generation = supersedeInFlightTap()
        performResolve(url, generation: generation) { result in
            // A newer tap arrived while this one was retrying. One tap means one
            // delivery, so the superseded one stays silent. `dispatchToOnLink`
            // is not an option for this: it takes an optional link and this
            // completion does not, so `.success(nil)` would not compile.
            guard isCurrentTap(generation) else { return }
            dispatchToOnLink(result.map { Optional($0) })
        }
        return true
    }

    /// Whether `url` is a WarpLink Universal Link this SDK would claim: a host
    /// in the known link-domain set AND a path that carries a slug (exactly one
    /// segment).
    ///
    /// This is the check `open(_:)` already makes, exposed. `open(_:)` asks it
    /// before it touches anything else, so a URL it refuses never reaches
    /// `shouldSuppressDuplicate`, never claims a tap, and never supersedes a
    /// link still resolving. `performResolve` refuses the same set with
    /// `WarpLinkError.invalidURL`.
    ///
    /// Exposed because a host that forwards every incoming URL, an app with its
    /// own router or the React Native bridge, has to ask the same question at
    /// the same point. Learning it afterwards from an `invalidURL` failure is
    /// too late to undo state a claim has already changed.
    ///
    /// Pure: it reads the known-domain set and returns. It resolves nothing,
    /// claims nothing, and touches no network. It does not require
    /// `configure(apiKey:options:)`, and deliberately does not check
    /// `autoDeepLinkHandling`: it answers what the URL is, not what the SDK
    /// would do with it.
    ///
    /// Before `configure(apiKey:options:)` the known set is the default domain
    /// alone, `aplnk.to`, which is what `localDomains` starts with. A link on a
    /// custom domain therefore reads as false until `configure` has declared it
    /// (`WarpLinkOptions.linkDomains` or the `WarpLinkDomains` Info.plist array)
    /// or `/sdk/validate` has returned it.
    public static func isWarpLinkURL(_ url: URL) -> Bool {
        url.isWarpLinkUniversalLink(domains: knownDomains())
    }

    /// Deliver an `NSUserActivity` (Universal Link) to the SDK (host one-liner,
    /// e.g. from `application(_:continue:restorationHandler:)`).
    @discardableResult
    public static func `continue`(_ userActivity: NSUserActivity) -> Bool {
        guard let url = userActivity.webpageURL else { return false }
        return open(url)
    }

    // MARK: - Internal

    /// Shared resolution primitive used by both the manual `handleDeepLink`
    /// path and the auto `open`/`continue` path.
    ///
    /// - Parameter generation: the tap generation this resolve belongs to, or
    ///   nil for a manual caller. A manual caller is never superseded: it asked
    ///   about one URL and is owed an answer.
    static func performResolve(
        _ url: URL,
        generation: Int? = nil,
        completion: @escaping (Result<WarpLinkDeepLink, WarpLinkError>) -> Void
    ) {
        guard isConfigured else {
            completion(.failure(.notConfigured))
            return
        }
        guard url.isWarpLinkUniversalLink(domains: knownDomains()),
              let slug = url.warpLinkSlug else {
            SDKEnvironment.deliver { completion(.failure(.invalidURL)) }
            return
        }

        lock.lock(); let client = apiClient; let log = logger; lock.unlock()

        guard let client = client else {
            SDKEnvironment.deliver { completion(.failure(.notConfigured)) }
            return
        }

        log?.log("Resolving Universal Link: \(url.absoluteString)")
        retryResolve(url, slug: slug, client: client, generation: generation) { result in
            deliverResolved(
                result, url: url, generation: generation, log: log, completion: completion
            )
        }
    }

    // MARK: - Private

    /// Ask the server for `slug` up to `RetryPolicy.maxAttempts` times.
    ///
    /// Extracted rather than inlined: `performResolve` was already over the
    /// fifty line cap before the retry existed.
    private static func retryResolve(
        _ url: URL,
        slug: String,
        client: APIClient,
        generation: Int?,
        completion: @escaping (Result<LinkResolutionResponse, WarpLinkError>) -> Void
    ) {
        // The folded host, so the domain sent to the resolve endpoint is spelled
        // the way the link was stored rather than the way iOS handed it over.
        let domain = url.warpLinkHost ?? defaultDomain
        // The raw query, encoded once by the client for transport, so the
        // server's single decode hands its query parser the same bytes a
        // browser sends and both paths reshape the link's URLs identically.
        let params = URLComponents(
            url: url, resolvingAgainstBaseURL: false
        )?.percentEncodedQuery
        // One id for this tap, minted once and repeated on every attempt.
        // Without it a retried attempt whose response was lost would bill a
        // second click for one tap.
        let tapId = UUID().uuidString

        BoundedRetry.run(
            isCurrent: { isCurrentTap(generation) },
            attempt: { number, done in
                let timeout = RetryPolicy.timeout(forAttempt: number)
                // EVERY attempt is bounded, the first included, and bounded in
                // WALL TIME rather than only between bytes. The SDK sets no
                // timeout of its own anywhere in Sources/, so an unbounded first
                // attempt inherits URLSession's 60 second default; and
                // `timeoutInterval` alone never ends an attempt that keeps
                // receiving bytes, so the watchdog is what makes the budget hold
                // for every failure shape rather than only for a silent one.
                //
                // And a timed-out or OS-cancelled attempt drops its connection,
                // or on HTTP/2 the retry rides the same dead connection it
                // failed on.
                let task = AttemptWatchdog.bound(
                    timeout: timeout,
                    completion: done,
                    discardConnection: { client.transport.discardConnections() }
                ) { answer in
                    client.resolveLink(
                        slug: slug, domain: domain, params: params, tapId: tapId,
                        timeout: timeout, completion: answer
                    )
                }
                // Recorded so a newer tap can cancel this attempt rather than
                // merely ignore its answer.
                setInFlightTap(task, generation: generation)
            },
            completion: completion
        )
    }

    /// Named `deliverResolved` rather than `deliver` so nothing in this file
    /// reads as a call to `SDKEnvironment.deliver`, which does something else.
    private static func deliverResolved(
        _ result: Result<LinkResolutionResponse, WarpLinkError>,
        url: URL,
        generation: Int?,
        log: Logger?,
        completion: @escaping (Result<WarpLinkDeepLink, WarpLinkError>) -> Void
    ) {
        switch result {
        case let .success(response):
            log?.log("Resolved link: \(response.slug)")
            completion(.success(deepLink(from: response)))
        case let .failure(error):
            log?.log("Failed to resolve link: \(error.localizedDescription)")
            // Android drops its claim on a failed resolve and iOS did not, so a
            // user's own re-tap inside the dedupe window was swallowed and the
            // link was lost for good. Released here, where every attempt has
            // already been spent. Only on failure: a successful resolve keeps
            // its claim, which is what stops a double delivery.
            //
            // And only while THIS tap still owns the claim. A re-tap of the
            // same link past the window stamps a fresh claim and cancels this
            // one, so the URL guard inside `releaseDuplicateClaim` cannot tell
            // the two apart: it sees its own URL and clears the newer tap's
            // claim. The newer tap's duplicate then gets through, supersedes it
            // and resolves again under a NEW tap id, which bills a second click
            // for one tap. The tap id cannot collapse that, because the second
            // resolve mints its own.
            if isCurrentTap(generation) {
                releaseDuplicateClaim(url)
            }
            completion(.failure(error))
        }
    }

    private static func deepLink(from response: LinkResolutionResponse) -> WarpLinkDeepLink {
        WarpLinkDeepLink(
            linkId: response.id,
            destination: response.destinationUrl,
            deepLinkUrl: response.iosUrl,
            customParams: response.customParams,
            isDeferred: false,
            matchType: .deterministic,
            matchConfidence: 1.0,
            // Resolved straight from the link, so the answer is certain.
            // Android's LinkResolver reports the same.
            matchGuaranteed: true
        )
    }
}
