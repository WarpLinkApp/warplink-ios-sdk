import Foundation

/// The set of hosts the SDK treats as WarpLink link domains.
///
/// It is split in two by WHEN each half becomes available, because the decision
/// it feeds cannot wait. `WarpLink.open(_:)` answers "is this link mine, or do
/// you route it?" synchronously, from inside `application(_:continue:)`, which
/// itself must return a `Bool` at once. A domain set that is only correct after
/// `/sdk/validate` answers is therefore wrong on a first launch, and on every
/// launch that has never reached the network: the link is handed back to the
/// host app, which has no route for it.
///
/// So the developer declares their own domains, in code or in the Info.plist,
/// and those are known the instant `configure()` returns. The server list stays
/// as a second source, which keeps every integration that declares nothing
/// working exactly as before.
extension WarpLink {

    /// Hosts known without a network call: `aplnk.to`, `options.linkDomains`,
    /// and the Info.plist declaration. Established synchronously by `configure()`.
    static var localDomains: Set<String> = [WarpLink.defaultDomain]

    /// Hosts learned from `/sdk/validate`: the live response, or the copy cached
    /// from an earlier launch.
    static var serverDomains: Set<String> = []

    /// Where the Info.plist declaration is read from. Injectable for tests, and
    /// restored to `Bundle.main` by `reset()` so an injected stub cannot leak
    /// into another test.
    static var domainDeclarationSource: LinkDomainDeclaring = Bundle.main

    /// The current set of hosts the SDK treats as WarpLink link domains: the
    /// union of the locally declared and the server-supplied halves. A union,
    /// not a precedence, because either half alone is a valid answer.
    static func knownDomains() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return localDomains.union(serverDomains)
    }

    /// The hosts declarable without the network, for one `configure()` call.
    ///
    /// Computed before `configure()` takes the lock, so it takes the lock itself
    /// only to read the injected source.
    static func resolveLocalDomains(options: WarpLinkOptions) -> Set<String> {
        lock.lock(); let source = domainDeclarationSource; lock.unlock()

        var domains: Set<String> = [WarpLink.defaultDomain]
        domains.formUnion(LinkDomainNormalizer.normalizeAll(options.linkDomains))
        domains.formUnion(LinkDomainNormalizer.normalizeAll(source.declaredLinkDomains()))
        return domains
    }

    /// Record the hosts `/sdk/validate` returned, and cache them for the next
    /// launch.
    ///
    /// The locally declared half is deliberately left alone. A server answer
    /// adds hosts; it never revokes the ones the developer declared, which are
    /// the only ones an offline launch has.
    ///
    /// An empty list is ignored rather than stored: the SDK cannot tell "this
    /// org has no custom domains" from a response that lost them, and treating
    /// the two alike would clear a good cache.
    static func applyServerDomains(_ domains: [String], storage: Storage) {
        guard !domains.isEmpty else { return }
        lock.lock()
        storage.cachedDomains = domains
        serverDomains = LinkDomainNormalizer.normalizeAll(domains)
        lock.unlock()
    }
}
