import Foundation

extension APIClient {

    /// Request attribution match from the server using raw device signals.
    ///
    /// - Parameter isReinstall: whether this device completed WarpLink
    ///   attribution once before, under an earlier install. Sent on every
    ///   request rather than only when true: the server reads an absent field as
    ///   "SDK too old to know", which is a different fact from a known `false`.
    /// - Parameter tapId: one id for the tap this request belongs to, repeated
    ///   on every attempt of that tap.
    /// - Parameter timeout: this attempt's own timeout, set on every attempt
    ///   including the first. Nil for a caller that is not retrying.
    /// - Returns: the request now on the wire, so a caller that is superseded
    ///   can stop it rather than merely ignore its answer.
    @discardableResult
    func matchAttribution(
        signals: DeviceSignals,
        sdkVersion: String,
        deviceId: String?,
        isReinstall: Bool,
        tapId: String? = nil,
        timeout: TimeInterval? = nil,
        completion: @escaping (Result<AttributionResponse, WarpLinkError>) -> Void
    ) -> HTTPTask {
        guard let url = URL(string: "\(baseURL)/attribution/match") else {
            completion(.failure(.serverError(statusCode: 0, message: "Invalid URL")))
            return CompletedHTTPTask()
        }

        var request = makeAttributionRequest(url: url, tapId: tapId, timeout: timeout)
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: attributionBody(
                signals: signals,
                sdkVersion: sdkVersion,
                deviceId: deviceId,
                isReinstall: isReinstall
            ))
        } catch {
            completion(.failure(.decodingError(error)))
            return CompletedHTTPTask()
        }

        return transport.send(request) { data, response, error in
            let result = Self.parseAttributionResponse(data: data, response: response, error: error)
            SDKEnvironment.deliver { completion(result) }
        }
    }

    // MARK: - Private

    /// The POST this endpoint takes, minus its body. Built by hand rather than
    /// through `makeAuthorizedRequest`, which is the GET builder.
    func makeAttributionRequest(
        url: URL, tapId: String?, timeout: TimeInterval?
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("WarpLink-iOS/\(WarpLink.sdkVersion)", forHTTPHeaderField: "User-Agent")
        if let tapId = tapId {
            // Log-only here. `app_installs.click_id` is uniquely indexed, but
            // the server derives its value from the deferred payload rather
            // than from the client, so this header does no dedupe work on this
            // endpoint. Sent so one attribution attempt is traceable across
            // its retries.
            request.setValue(tapId, forHTTPHeaderField: Self.tapIdHeader)
        }
        if let timeout = timeout {
            request.timeoutInterval = timeout
        }
        return request
    }

    private func attributionBody(
        signals: DeviceSignals, sdkVersion: String, deviceId: String?, isReinstall: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [
            "accept_language": signals.acceptLanguage,
            // Offset stays for servers that have not shipped zone-name matching.
            "timezone_offset": signals.timezoneOffset,
            "platform": "ios",
            "fingerprint_version": signals.timezone.isEmpty ? "enriched" : "enriched_tz",
            "sdk_version": sdkVersion,
            "is_reinstall": isReinstall,
        ]
        // The IANA zone carries far more entropy than the offset and does not
        // shift at a daylight-saving boundary, so the server prefers it.
        if !signals.timezone.isEmpty {
            body["timezone"] = signals.timezone
        }
        if let deviceId = deviceId {
            body["device_id"] = deviceId
        }
        // Omitted rather than sent empty: the server rejects an empty value,
        // which would fail the whole request instead of falling back to the
        // org-wide lookup.
        if let bundleIdentifier = bundleIdentifier, !bundleIdentifier.isEmpty {
            body["app_bundle_id"] = bundleIdentifier
        }
        return body
    }

    private static func parseAttributionResponse(
        data: Data?, response: URLResponse?, error: Error?
    ) -> Result<AttributionResponse, WarpLinkError> {
        if let error = error { return .failure(.networkError(error)) }
        guard let http = response as? HTTPURLResponse else {
            return .failure(.serverError(statusCode: 0, message: "No HTTP response"))
        }
        switch http.statusCode {
        case 200:
            return AttributionResponse.decode(data: data)
        case 401, 403:
            return .failure(.invalidApiKey)
        case RateLimit.statusCode:
            return .failure(RateLimit.error(for: http))
        default:
            return .failure(.serverError(statusCode: http.statusCode, message: "Server error"))
        }
    }
}
