import Foundation

/// Server response for a link resolution request.
struct LinkResolutionResponse {
    let id: String
    let slug: String
    let domain: String
    let destinationUrl: String
    let iosUrl: String?
    let iosFallbackUrl: String?
    let customParams: [String: Any]
    let createdAt: String
}

extension APIClient {

    /// Resolve a link by slug and domain.
    ///
    /// - Parameters:
    ///   - slug: The link slug to resolve.
    ///   - domain: The domain the link belongs to.
    ///   - completion: Called with the link resolution response or an error.
    func resolveLink(
        slug: String,
        domain: String,
        completion: @escaping (Result<LinkResolutionResponse, WarpLinkError>) -> Void
    ) {
        guard let url = buildResolveLinkURL(slug: slug, domain: domain) else {
            completion(.failure(.serverError(statusCode: 0, message: "Invalid URL")))
            return
        }

        let request = makeAuthorizedRequest(url: url)

        session.dataTask(with: request) { data, response, error in
            let result = Self.parseResolveLinkResponse(
                data: data, response: response, error: error
            )
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    // MARK: - Private Helpers

    private func buildResolveLinkURL(slug: String, domain: String) -> URL? {
        var components = URLComponents(string: "\(baseURL)/links/resolve/\(slug)")
        components?.queryItems = [URLQueryItem(name: "domain", value: domain)]
        return components?.url
    }

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
            return .failure(.linkNotFound)
        case 401, 403:
            return .failure(.invalidApiKey)
        default:
            return .failure(.serverError(
                statusCode: httpResponse.statusCode,
                message: "Unexpected status code"
            ))
        }
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
            customParams: json["custom_params"] as? [String: Any] ?? [:],
            createdAt: createdAt
        ))
    }
}
