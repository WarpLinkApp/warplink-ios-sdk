import Foundation

extension WarpLinkDeepLink {

    /// What makes two links the same route for an app: the link id, or the
    /// destination address when there is no id. Match type and evidence are not
    /// part of it, so a stronger answer for the same link is not a new route.
    var routeIdentity: String {
        linkId.isEmpty ? "url:\(destination)" : "id:\(linkId)"
    }
}
