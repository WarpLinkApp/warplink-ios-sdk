import Foundation

/// Result of server-side API key validation, including the org's usable link
/// domains (so the SDK stops hardcoding `aplnk.to`).
struct ValidationResult {
    let valid: Bool
    let domains: [String]
}

/// HTTP client for WarpLink API calls. Uses URLSession with zero dependencies.
class APIClient {

    let baseURL: String
    let apiKey: String
    /// Injected rather than built here so a test can close the network boundary
    /// entirely. See `SDKEnvironment`.
    let transport: HTTPTransport
    /// The host app's bundle identifier, sent with attribution requests so the
    /// server can tell which app of an organization this install belongs to.
    /// An API key is org-scoped, and every app from one Apple team shares an
    /// IDFV, so without this the server can match an install to a sibling app.
    let bundleIdentifier: String?

    init(
        apiKey: String,
        baseURL: String = "https://api.warplink.app/v1",
        transport: HTTPTransport = SDKEnvironment.makeTransport(),
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.transport = transport
        self.bundleIdentifier = bundleIdentifier
    }

    /// The wire name for the tap id. One id per tap, repeated on every attempt
    /// of that tap.
    ///
    /// On the resolve request the server uses it as the click's id, so an
    /// attempt whose response was lost is collapsed server-side instead of
    /// billing a second click for one tap. On the attribution request it is
    /// log-only: an install row is already protected by its own server-side
    /// unique constraint, whose key the server derives rather than accepts.
    static let tapIdHeader = "X-WarpLink-Tap-Id"

    /// Create a GET request with standard WarpLink auth headers.
    func makeAuthorizedRequest(url: URL, tapId: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("WarpLink-iOS/\(WarpLink.sdkVersion)", forHTTPHeaderField: "User-Agent")
        if let tapId = tapId {
            request.setValue(tapId, forHTTPHeaderField: Self.tapIdHeader)
        }
        return request
    }

    /// Validate the API key against the server and read the org's link domains.
    func validateApiKey(
        completion: @escaping (Result<ValidationResult, WarpLinkError>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/sdk/validate") else {
            completion(.failure(.serverError(statusCode: 0, message: "Invalid URL")))
            return
        }

        let request = makeAuthorizedRequest(url: url)
        transport.send(request) { data, response, error in
            let result = Self.parseValidation(data: data, response: response, error: error)
            SDKEnvironment.deliver { completion(result) }
        }
    }

    // MARK: - Private

    private static func parseValidation(
        data: Data?, response: URLResponse?, error: Error?
    ) -> Result<ValidationResult, WarpLinkError> {
        if let error = error { return .failure(.networkError(error)) }
        guard let http = response as? HTTPURLResponse else {
            return .failure(.serverError(statusCode: 0, message: "No HTTP response"))
        }
        switch http.statusCode {
        case 200:
            let json = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            let valid = (json?["valid"] as? Bool) ?? true
            let domains = (json?["domains"] as? [String]) ?? []
            return .success(ValidationResult(valid: valid, domains: domains))
        case 401, 403:
            return .success(ValidationResult(valid: false, domains: []))
        default:
            return .failure(.serverError(statusCode: http.statusCode, message: "Unexpected status code"))
        }
    }
}
