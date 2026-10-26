import Foundation

extension APIClient {

    /// Redeems a pasted recovery token through the match route.
    ///
    /// The request carries the token and the device id (IDFV), nothing that
    /// could match on its own. The server refuses a bad token with a 400 unless
    /// a referrer or device signals travel with it, and a device id does not
    /// count as one: it only lets the server read a repeat from the install that
    /// already holds the token as the original answer. Sending device signals
    /// here would let a bad token fall through to a guess, and the user would
    /// never hear that the invitation was unusable.
    @discardableResult
    func redeemRecoveryToken(
        _ token: String,
        deviceId: String?,
        sdkVersion: String,
        isReinstall: Bool,
        timeout: TimeInterval,
        completion: @escaping (Result<RecoveryRedeemOutcome, WarpLinkError>) -> Void
    ) -> HTTPTask {
        guard let url = URL(string: "\(baseURL)/attribution/match") else {
            completion(.failure(.serverError(statusCode: 0, message: "Invalid URL")))
            return CompletedHTTPTask()
        }
        var request = makeAttributionRequest(url: url, tapId: nil, timeout: timeout)
        var body: [String: Any] = [
            "platform": "ios",
            "fingerprint_version": "enriched",
            "sdk_version": sdkVersion,
            "is_reinstall": isReinstall,
            "recovery_token": token,
        ]
        if let deviceId = deviceId, !deviceId.isEmpty {
            body["device_id"] = deviceId
        }
        if let bundleIdentifier = bundleIdentifier, !bundleIdentifier.isEmpty {
            body["app_bundle_id"] = bundleIdentifier
        }
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(.decodingError(error)))
            return CompletedHTTPTask()
        }
        return transport.send(request) { data, response, error in
            let result = Self.redeemResult(data: data, response: response, error: error)
            SDKEnvironment.deliver { completion(result) }
        }
    }

    private static func redeemResult(
        data: Data?, response: URLResponse?, error: Error?
    ) -> Result<RecoveryRedeemOutcome, WarpLinkError> {
        switch ReferralHTTP.failure(data: data, response: response, error: error) {
        case let .refused(refusal)?: return .success(.refused(refusal))
        case let .failed(error)?: return .failure(error)
        case nil: return AttributionResponse.decode(data: data).map(RecoveryRedeemOutcome.answered)
        }
    }
}
