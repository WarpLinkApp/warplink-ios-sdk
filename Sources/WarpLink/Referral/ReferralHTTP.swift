import Foundation

/// Reading the answers of the two referral routes.
enum ReferralHTTP {

    static let tokenExpiredCode = "RECOVERY_TOKEN_EXPIRED"
    static let tokenInvalidCode = "RECOVERY_TOKEN_INVALID"
    static let tokenPendingCode = "RECOVERY_TOKEN_PENDING"

    /// The `error` object of an API error body.
    struct ErrorBody {
        let code: String?
        let message: String?
    }

    /// Why a referral request failed. A refusal is read from the server's error
    /// code here, where it is known, so no caller has to recognise one by the
    /// text of its message.
    enum Failure {
        /// The server refused the token. Asking again with it would be refused again.
        case refused(ReferralMessages.Refusal)
        case failed(WarpLinkError)

        var error: WarpLinkError {
            switch self {
            case let .refused(refusal): return refusal.error
            case let .failed(error): return error
            }
        }
    }

    static func errorBody(_ data: Data?) -> ErrorBody {
        let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let error = object?["error"] as? [String: Any]
        return ErrorBody(code: error?["code"] as? String, message: error?["message"] as? String)
    }

    /// The failure for a response that is not a 200, or nil for a 200.
    ///
    /// A 400 that refuses the token is a refusal and carries the
    /// reopen-the-invitation message. A 503 that says the token is not confirmed
    /// yet carries the try-again message and is not a refusal, so the invitation
    /// is kept for a retry. Every other failure keeps what the server said,
    /// because the message is written for the developer who called the route and
    /// holds no secret.
    static func failure(
        data: Data?, response: URLResponse?, error: Error?
    ) -> Failure? {
        if let error = error { return .failed(.networkError(error)) }
        guard let http = response as? HTTPURLResponse else {
            return .failed(.serverError(statusCode: 0, message: "No HTTP response"))
        }
        switch http.statusCode {
        case 200: return nil
        case 401: return .failed(.invalidApiKey)
        case RateLimit.statusCode: return .failed(RateLimit.error(for: http))
        case ReferralMessages.refusalStatus: return badRequest(errorBody(data))
        case ReferralMessages.pendingStatus where errorBody(data).code == tokenPendingCode:
            return .failed(
                .serverError(
                    statusCode: ReferralMessages.pendingStatus,
                    message: ReferralMessages.pendingInvitation
                )
            )
        default:
            return .failed(
                .serverError(
                    statusCode: http.statusCode,
                    message: errorBody(data).message ?? "Server error"
                )
            )
        }
    }

    private static func badRequest(_ body: ErrorBody) -> Failure {
        switch body.code {
        case tokenExpiredCode:
            return .refused(.unusable)
        case tokenInvalidCode:
            return .refused(.invalid)
        default:
            return .failed(
                .serverError(
                    statusCode: ReferralMessages.refusalStatus,
                    message: body.message ?? "Server error"
                )
            )
        }
    }
}
