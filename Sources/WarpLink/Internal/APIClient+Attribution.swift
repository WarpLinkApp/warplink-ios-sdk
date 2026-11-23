import Foundation

extension APIClient {

    /// Request attribution match from the server using raw device signals, or
    /// with none.
    ///
    /// - Parameter signals: the raw device signals. Nil leaves them out, so the
    ///   server uses only the stronger paths (device id, Tether code).
    /// - Parameter isReinstall: whether this device completed WarpLink
    ///   attribution once before, under an earlier install. Sent on every
    ///   request rather than only when true: the server reads an absent field as
    ///   "SDK too old to know", which is a different fact from a known `false`.
    /// - Parameter tapId: one id for the tap this request belongs to, repeated
    ///   on every attempt of that tap.
    /// - Parameter tether: the installation id and any Tether code or miss to
    ///   report with this request. Nil sends none of them.
    /// - Parameter attemptNumber: which launch of this install sent a deferred
    ///   check. The same on every in-launch retry. Nil sends none.
    /// - Parameter timeout: this attempt's own timeout, set on every attempt
    ///   including the first. Nil for a caller that is not retrying.
    /// - Parameter onDecoded: called with a decoded 200 answer on the thread the
    ///   transport answers on, before the result is handed to `completion` on
    ///   the main queue. For work that must not wait for that hop.
    /// - Returns: the request now on the wire, so a caller that is superseded
    ///   can stop it rather than merely ignore its answer.
    @discardableResult
    func matchAttribution(
        signals: DeviceSignals?,
        sdkVersion: String,
        deviceId: String?,
        isReinstall: Bool,
        tapId: String? = nil,
        tether: TetherRequestFields? = nil,
        attemptNumber: Int? = nil,
        timeout: TimeInterval? = nil,
        onDecoded: ((AttributionResponse) -> Void)? = nil,
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
                isReinstall: isReinstall,
                tether: tether,
                attemptNumber: attemptNumber
            ))
        } catch {
            completion(.failure(.decodingError(error)))
            return CompletedHTTPTask()
        }

        return transport.send(request) { data, response, error in
            let result = Self.parseAttributionResponse(data: data, response: response, error: error)
            if case let .success(decoded) = result { onDecoded?(decoded) }
            SDKEnvironment.deliver { completion(result) }
        }
    }

    // MARK: - Request building

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
        signals: DeviceSignals?, sdkVersion: String, deviceId: String?, isReinstall: Bool,
        tether: TetherRequestFields?, attemptNumber: Int?
    ) -> [String: Any] {
        var body: [String: Any] = [
            "platform": "ios",
            // The server requires a version. With no raw signals it matches on
            // the stronger paths only and ignores this value.
            "fingerprint_version": "enriched",
            "sdk_version": sdkVersion,
            "is_reinstall": isReinstall,
        ]
        if let signals = signals { writeRawSignals(signals, to: &body) }
        if let attemptNumber = attemptNumber {
            body["attempt_number"] = attemptNumber
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
        tether?.write(to: &body)
        return body
    }

    private func writeRawSignals(_ signals: DeviceSignals, to body: inout [String: Any]) {
        body["accept_language"] = signals.acceptLanguage
        // Offset stays for servers that have not shipped zone-name matching.
        body["timezone_offset"] = signals.timezoneOffset
        body["fingerprint_version"] = signals.timezone.isEmpty ? "enriched" : "enriched_tz"
        // The IANA zone carries far more entropy than the offset and does not
        // shift at a daylight-saving boundary, so the server prefers it.
        if !signals.timezone.isEmpty {
            body["timezone"] = signals.timezone
        }
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
