import Foundation

extension APIClient {

    /// Claims the referral behind this install for `installerId`.
    ///
    /// Claiming is idempotent on the server for one installer, so a retried
    /// request cannot credit twice.
    ///
    /// `onTokenRefused` runs when the server refuses the token the claim
    /// carried. The caller still gets the `none` answer; the callback lets it
    /// drop a token that every later claim would see refused again.
    @discardableResult
    func claimReferral(
        installerId: String,
        evidence: ReferralClaimEvidence,
        timeout: TimeInterval,
        onTokenRefused: @escaping () -> Void = {},
        completion: @escaping (Result<ReferralClaimResult, WarpLinkError>) -> Void
    ) -> HTTPTask {
        guard let url = URL(string: "\(baseURL)/referrals/claims") else {
            completion(.failure(.serverError(statusCode: 0, message: "Invalid URL")))
            return CompletedHTTPTask()
        }
        var request = makeAttributionRequest(url: url, tapId: nil, timeout: timeout)
        do {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: evidence.body(installerId: installerId, bundleIdentifier: bundleIdentifier)
            )
        } catch {
            completion(.failure(.decodingError(error)))
            return CompletedHTTPTask()
        }
        return transport.send(request) { data, response, error in
            let failure = ReferralHTTP.failure(data: data, response: response, error: error)
            if case .refused? = failure { onTokenRefused() }
            let result = Self.claimResult(data: data, failure: failure)
            SDKEnvironment.deliver { completion(result) }
        }
    }

    /// A refused token is not a failed claim. The request carried the token
    /// and nothing else that names a referral, so the server has nothing to
    /// credit, which is the `none` answer.
    private static func claimResult(
        data: Data?, failure: ReferralHTTP.Failure?
    ) -> Result<ReferralClaimResult, WarpLinkError> {
        switch failure {
        case .refused?: return .success(.none)
        case let .failed(error)?: return .failure(error)
        case nil: break
        }
        return .success(ReferralClaimResult.decode(data: data))
    }
}
