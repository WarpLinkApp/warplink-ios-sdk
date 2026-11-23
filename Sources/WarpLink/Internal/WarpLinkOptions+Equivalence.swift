import Foundation

extension WarpLinkOptions {

    /// Whether `other` asks for the same session as these options.
    ///
    /// Every field counts except `onLink`: a closure cannot be compared, and a
    /// host that configures twice with a new handler still means the same session.
    func isEquivalent(to other: WarpLinkOptions) -> Bool {
        apiEndpoint == other.apiEndpoint
            && debugLogging == other.debugLogging
            && autoDeepLinkHandling == other.autoDeepLinkHandling
            && autoDeferredCheck == other.autoDeferredCheck
            && linkDomains == other.linkDomains
            && tetherReadMode == other.tetherReadMode
    }
}
