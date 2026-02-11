import Foundation

/// Server response for an attribution match request.
struct AttributionResponse {
    let matched: Bool
    let matchType: String?
    let matchConfidence: Double?
    let linkId: String?
    let deepLinkUrl: String?
    let destinationUrl: String?
    let customParams: [String: Any]?
    let installId: String?
}

/// HTTP client for WarpLink API calls. Uses URLSession with zero dependencies.
class APIClient {

    let baseURL: String
    let apiKey: String
    let session: URLSession

    init(
        apiKey: String,
        baseURL: String = "https://api.warplink.app/v1",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    /// Create a GET request with standard WarpLink auth headers.
    func makeAuthorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "WarpLink-iOS/\(WarpLink.sdkVersion)",
            forHTTPHeaderField: "User-Agent"
        )
        return request
    }

    /// Validate the API key against the server.
    func validateApiKey(
        completion: @escaping (Result<Bool, WarpLinkError>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/sdk/validate") else {
            completion(.failure(.serverError(statusCode: 0, message: "Invalid URL")))
            return
        }

        let request = makeAuthorizedRequest(url: url)

        session.dataTask(with: request) { _, response, error in
            let result: Result<Bool, WarpLinkError> = {
                if let error = error {
                    return .failure(.networkError(error))
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    return .failure(.serverError(statusCode: 0, message: "No HTTP response"))
                }
                switch httpResponse.statusCode {
                case 200:
                    return .success(true)
                case 401, 403:
                    return .success(false)
                default:
                    return .failure(.serverError(
                        statusCode: httpResponse.statusCode,
                        message: "Unexpected status code"
                    ))
                }
            }()
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// Request attribution match from the server using raw device signals.
    func matchAttribution(
        signals: DeviceSignals,
        sdkVersion: String,
        deviceId: String?,
        completion: @escaping (Result<AttributionResponse, WarpLinkError>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/attribution/match") else {
            completion(.failure(.serverError(statusCode: 0, message: "Invalid URL")))
            return
        }

        var body: [String: Any] = [
            "accept_language": signals.acceptLanguage,
            "screen_width": signals.screenWidth,
            "screen_height": signals.screenHeight,
            "timezone_offset": signals.timezoneOffset,
            "user_agent": signals.userAgent,
            "platform": "ios",
            "fingerprint_version": "enriched",
            "sdk_version": sdkVersion,
        ]
        if let deviceId = deviceId {
            body["device_id"] = deviceId
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "WarpLink-iOS/\(WarpLink.sdkVersion)",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(.decodingError(error)))
            return
        }

        session.dataTask(with: request) { data, response, error in
            let result = Self.parseAttributionResponse(
                data: data, response: response, error: error
            )
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    // MARK: - Private

    private static func parseAttributionResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) -> Result<AttributionResponse, WarpLinkError> {
        if let error = error {
            return .failure(.networkError(error))
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.serverError(statusCode: 0, message: "No HTTP response"))
        }
        switch httpResponse.statusCode {
        case 200:
            return decodeAttributionBody(data: data)
        case 401, 403:
            return .failure(.invalidApiKey)
        default:
            return .failure(.serverError(
                statusCode: httpResponse.statusCode,
                message: "Server error"
            ))
        }
    }

    private static func decodeAttributionBody(
        data: Data?
    ) -> Result<AttributionResponse, WarpLinkError> {
        guard let data = data else {
            return .failure(.serverError(statusCode: 200, message: "Empty response"))
        }
        do {
            guard let json = try JSONSerialization.jsonObject(
                with: data
            ) as? [String: Any] else {
                return .failure(.decodingError(
                    NSError(domain: "WarpLink", code: 0, userInfo: [
                        NSLocalizedDescriptionKey: "Response is not a JSON object",
                    ])
                ))
            }
            let matched = json["matched"] as? Bool ?? false
            return .success(AttributionResponse(
                matched: matched,
                matchType: json["match_type"] as? String,
                matchConfidence: json["match_confidence"] as? Double,
                linkId: json["link_id"] as? String,
                deepLinkUrl: json["deep_link_url"] as? String,
                destinationUrl: json["destination_url"] as? String,
                customParams: json["custom_params"] as? [String: Any],
                installId: json["install_id"] as? String
            ))
        } catch {
            return .failure(.decodingError(error))
        }
    }
}
