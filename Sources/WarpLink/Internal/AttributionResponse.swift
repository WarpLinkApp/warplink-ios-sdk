import Foundation

/// Server response for an attribution match request.
struct AttributionResponse {
    let matched: Bool
    let matchType: String?
    let matchConfidence: Double?
    let matchGuaranteed: Bool
    let linkId: String?
    let deepLinkUrl: String?
    let destinationUrl: String?
    let customParams: [String: JSONValue]?
    let installId: String?
    let attributionId: String?
    let matchMethod: String?
    let evidenceClass: String?
    let replayState: String?
    let capturedParams: [String: JSONValue]?
    let tappedAt: String?
}

extension AttributionResponse {

    static func decode(
        data: Data?
    ) -> Result<AttributionResponse, WarpLinkError> {
        guard let data = data else {
            return .failure(.serverError(statusCode: 200, message: "Empty response"))
        }
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.decodingError(
                    NSError(domain: "WarpLink", code: 0, userInfo: [
                        NSLocalizedDescriptionKey: "Response is not a JSON object",
                    ])
                ))
            }
            return .success(AttributionResponse(json: json))
        } catch {
            return .failure(.decodingError(error))
        }
    }

    private init(json: [String: Any]) {
        matched = json["matched"] as? Bool ?? false
        matchType = json["match_type"] as? String
        matchConfidence = json["match_confidence"] as? Double
        matchGuaranteed = json["match_guaranteed"] as? Bool ?? false
        linkId = json["link_id"] as? String
        deepLinkUrl = json["deep_link_url"] as? String
        destinationUrl = json["destination_url"] as? String
        customParams = Self.params(json["custom_params"])
        installId = json["install_id"] as? String
        attributionId = json["attribution_id"] as? String
        matchMethod = json["match_method"] as? String
        evidenceClass = json["evidence_class"] as? String
        replayState = json["replay_state"] as? String
        capturedParams = Self.params(json["captured_params"])
        tappedAt = json["tapped_at"] as? String
    }

    private static func params(_ value: Any?) -> [String: JSONValue]? {
        (value as? [String: Any])?.mapValues { JSONValue(any: $0) }
    }
}
