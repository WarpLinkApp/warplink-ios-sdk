import Foundation

/// Server response for a link resolution request.
struct LinkResolutionResponse {
    let id: String
    let slug: String
    let domain: String
    let destinationUrl: String
    let iosUrl: String?
    let iosFallbackUrl: String?
    let customParams: [String: JSONValue]
    let createdAt: String
}

/// The API's error code for a link whose password has not been supplied.
private let passwordRequiredCode = "PASSWORD_REQUIRED"

extension APIClient {

    /// Resolve a link by slug and domain.
    ///
    /// - Parameters:
    ///   - slug: The link slug to resolve.
    ///   - domain: The domain the link belongs to.
    ///   - params: The tapped URL's raw, percent-encoded query string, as
    ///     `URLComponents.percentEncodedQuery` gives it. The server decodes it
    ///     once and parses the result as a query string, so raw is the only
    ///     form that survives: a decoded source turns `x%26y` into two
    ///     parameters and reads the `+` in `a%2Bb%40x.com` as a space. The
    ///     server reshapes the link's URLs with it, so a link's UTM and custom
    ///     parameters survive an in-app open exactly as they survive a
    ///     redirect. Nil when the tapped URL carried no query.
    ///   - tapId: one id for the tap this request belongs to, repeated on every
    ///     attempt of that tap. Nil when the caller is not retrying, which is
    ///     every path except the bounded resolve retry.
    ///   - timeout: this attempt's own timeout. The bounded retry sets one on
    ///     EVERY attempt, the first included: the SDK sets no timeout of its own
    ///     anywhere in Sources/, so an unbounded attempt inherits URLSession's
    ///     60 second default and spends a whole retry budget by itself on a
    ///     network that hangs rather than fails. Nil only for a caller that is
    ///     not retrying.
    ///   - completion: Called with the link resolution response or an error.
    /// - Returns: the request now on the wire, so a caller that is superseded
    ///   can stop it rather than merely ignore its answer.
    @discardableResult
    func resolveLink(
        slug: String,
        domain: String,
        params: String? = nil,
        tapId: String? = nil,
        timeout: TimeInterval? = nil,
        completion: @escaping (Result<LinkResolutionResponse, WarpLinkError>) -> Void
    ) -> HTTPTask {
        guard let url = buildResolveLinkURL(slug: slug, domain: domain, params: params) else {
            completion(.failure(.serverError(statusCode: 0, message: "Invalid URL")))
            return CompletedHTTPTask()
        }

        var request = makeAuthorizedRequest(url: url, tapId: tapId)
        if let timeout = timeout {
            request.timeoutInterval = timeout
        }

        return transport.send(request) { data, response, error in
            let result = Self.parseResolveLinkResponse(
                data: data, response: response, error: error
            )
            SDKEnvironment.deliver { completion(result) }
        }
    }

    // MARK: - Private Helpers

    private func buildResolveLinkURL(slug: String, domain: String, params: String?) -> URL? {
        var components = URLComponents(string: "\(baseURL)/links/resolve/\(slug)")
        components?.queryItems = [URLQueryItem(name: "domain", value: domain)]
        guard let params = params, !params.isEmpty else { return components?.url }

        // Appended to `percentEncodedQuery` rather than added as a query item:
        // `queryItems` encodes with `urlQueryAllowed`, which permits `&` and
        // `=`, so a query string handed to it would split into several
        // parameters at the server instead of arriving as one value.
        let encoded = params.addingPercentEncoding(
            withAllowedCharacters: Self.paramsValueAllowed
        ) ?? params
        let existing = components?.percentEncodedQuery ?? ""
        components?.percentEncodedQuery = existing + "&params=" + encoded
        return components?.url
    }

    /// RFC 3986's unreserved set. Everything else is escaped, so the value is
    /// encoded exactly once and the server's single decode returns the string
    /// the user tapped.
    private static let paramsValueAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func parseResolveLinkResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) -> Result<LinkResolutionResponse, WarpLinkError> {
        if let error = error {
            return .failure(.networkError(error))
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.serverError(statusCode: 0, message: "No HTTP response"))
        }
        switch httpResponse.statusCode {
        case 200:
            return decodeResolveLinkBody(data: data)
        case 404:
            // Also what a suspended custom domain answers with, deliberately:
            // the server refuses to say a domain exists but is not serving.
            return .failure(.linkNotFound)
        case 403:
            // A 403 is either a rejected key or a password protected link, and
            // only the body's error code tells them apart.
            return .failure(
                errorCode(in: data) == passwordRequiredCode ? .passwordRequired : .invalidApiKey
            )
        case 401:
            return .failure(.invalidApiKey)
        default:
            return .failure(.serverError(
                statusCode: httpResponse.statusCode,
                message: "Unexpected status code"
            ))
        }
    }

    /// The API's error code, from the documented `{"error":{"code":...}}` body.
    /// Nil when the refusal carried no body, or one this SDK cannot read: a
    /// malformed refusal must degrade to the generic mapping, never throw.
    private static func errorCode(in data: Data?) -> String? {
        guard let data = data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return nil
        }
        return error["code"] as? String
    }

    private static func decodeResolveLinkBody(
        data: Data?
    ) -> Result<LinkResolutionResponse, WarpLinkError> {
        guard let data = data else {
            return .failure(.serverError(statusCode: 200, message: "Empty response body"))
        }
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.decodingError(
                    NSError(domain: "WarpLink", code: 0, userInfo: [
                        NSLocalizedDescriptionKey: "Response is not a JSON object",
                    ])
                ))
            }
            return mapJsonToResponse(json)
        } catch {
            return .failure(.decodingError(error))
        }
    }

    private static func mapJsonToResponse(
        _ json: [String: Any]
    ) -> Result<LinkResolutionResponse, WarpLinkError> {
        guard let id = json["id"] as? String,
              let slug = json["slug"] as? String,
              let domain = json["domain"] as? String,
              let destinationUrl = json["destination_url"] as? String,
              let createdAt = json["created_at"] as? String else {
            return .failure(.decodingError(
                NSError(domain: "WarpLink", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "Missing required fields in response",
                ])
            ))
        }
        return .success(LinkResolutionResponse(
            id: id,
            slug: slug,
            domain: domain,
            destinationUrl: destinationUrl,
            iosUrl: json["ios_url"] as? String,
            iosFallbackUrl: json["ios_fallback_url"] as? String,
            customParams: (json["custom_params"] as? [String: Any])?.mapValues { JSONValue(any: $0) } ?? [:],
            createdAt: createdAt
        ))
    }
}
