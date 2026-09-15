import Foundation

extension URL {

    /// Whether this URL is a WarpLink Universal Link the SDK can resolve.
    ///
    /// Two conditions: the host is one of the SDK's known WarpLink domains, and
    /// the path carries a slug (see `warpLinkSlug`). The domain set is `aplnk.to`,
    /// plus the domains the host declares locally (`WarpLinkOptions.linkDomains`
    /// or the Info.plist declaration), plus any verified custom domains the
    /// server returns from `/sdk/validate`, cached by the SDK, so custom-domain
    /// Universal Links resolve on the first launch and without hardcoding.
    ///
    /// The slug condition matters because the `apple-app-site-association` file
    /// WarpLink publishes defaults to `paths: ["*"]`: iOS hands the app every
    /// URL on the domain, including marketing pages and multi-segment paths that
    /// are not links. Claiming those would swallow URLs the SDK cannot resolve
    /// instead of letting the host app's own router handle them.
    func isWarpLinkUniversalLink(domains: Set<String>) -> Bool {
        guard let host = warpLinkHost, domains.contains(host) else { return false }
        return warpLinkSlug != nil
    }

    /// The URL's host, folded the same way a declared domain is.
    ///
    /// `Foundation` preserves the case it was handed, so a link written
    /// `https://Links.Example.Com/abc123` arrives with that exact host. Hosts
    /// are case-insensitive, so comparing it raw against a normalized
    /// declaration would reject the developer's own domain over capitals they
    /// cannot control. Both sides fold to lowercase, once.
    var warpLinkHost: String? {
        host?.lowercased()
    }

    /// Extract the WarpLink slug from the URL path.
    ///
    /// A slug is always exactly one path segment: every server-side create path
    /// rejects `/` in a slug, and the redirect edge only matches single-segment
    /// paths. So `https://aplnk.to/abc123` returns `"abc123"`, while
    /// `https://aplnk.to/blog/hello` returns `nil` rather than `"blog"`, which
    /// would resolve an unrelated link that happens to be named `blog`.
    ///
    /// The guard is on segment count only, deliberately not on the server's slug
    /// character rules. Segment count is structural (a slug can never contain
    /// `/`), so it cannot drift the way a copy of those rules would once they
    /// loosen server-side, in a binary that is already shipped.
    ///
    /// A component that still contains a literal `/` (a percent-encoded `%2F`,
    /// which `pathComponents` decodes) is rejected too: the slug is interpolated
    /// into the resolve request URL.
    var warpLinkSlug: String? {
        let components = pathComponents.filter { $0 != "/" }
        guard components.count == 1, let slug = components.first else { return nil }
        guard !slug.isEmpty, !slug.contains("/") else { return nil }
        return slug
    }
}
