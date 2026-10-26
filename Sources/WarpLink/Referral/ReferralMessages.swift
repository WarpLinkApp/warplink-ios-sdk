import Foundation

/// What the user is told when an invitation cannot be used.
///
/// The refusal messages say how to get a usable invitation and that the app
/// keeps working without one. They are carried by `WarpLinkError.serverError` with
/// status 400, the status the server refuses a token with, so no new error case
/// is needed. `ReferralHTTP` reads a refusal from the server's error code, so
/// nothing recognises one by its message.
enum ReferralMessages {

    /// The reasons an invitation is refused.
    enum Refusal: Sendable {
        case invalid
        case expired
        /// For a refusal the server words as "expired". The same refusal covers a
        /// link that was paused or ended, so its message does not claim an expiry.
        case unusable

        var message: String {
            switch self {
            case .invalid:
                return "This invitation is not valid. Open the invitation link again, copy the "
                    + "invitation, and paste it here. You can also continue without it."
            case .expired:
                return "This invitation has expired. Open the invitation link again to get a "
                    + "fresh one, then paste it here. You can also continue without it."
            case .unusable:
                return "This invitation cannot be used right now. Open the invitation link "
                    + "again to get a fresh one, then paste it here. You can also continue "
                    + "without it."
            }
        }

        var error: WarpLinkError {
            .serverError(statusCode: ReferralMessages.refusalStatus, message: message)
        }
    }

    /// For a 503 while the server cannot confirm a just-issued invitation yet.
    /// It is not a refusal: the invitation is kept and tried again.
    static let pendingInvitation =
        "We could not confirm this invitation yet. Try again in a minute."

    static let refusalStatus = 400
    static let pendingStatus = 503
}
