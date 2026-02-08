import Foundation

extension URL {

    /// Whether this URL is a WarpLink Universal Link.
    ///
    /// Checks if the host matches known WarpLink domains.
    // TODO: Add support for custom domains via SDK configuration.
    var isWarpLinkUniversalLink: Bool {
        guard let host = self.host else { return false }
        let knownDomains = ["aplnk.to"]
        return knownDomains.contains(host)
    }

    /// Extract the WarpLink slug from the URL path.
    ///
    /// The slug is the first path component after `/`.
    /// For example, `https://aplnk.to/abc123` returns `"abc123"`.
    var warpLinkSlug: String? {
        let components = pathComponents.filter { $0 != "/" }
        return components.first
    }
}
