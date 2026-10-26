import Foundation

/// Turns a match response into the result a host receives.
enum ReferralMatch {

    /// The routable link in `response`, or nil when there is nothing to route to.
    ///
    /// A matched response that names no link or no destination is not routable:
    /// the caller must not treat it as an answer.
    static func deepLink(from response: AttributionResponse) -> WarpLinkDeepLink? {
        guard response.matched,
              let linkId = response.linkId,
              let destination = response.destinationUrl else { return nil }
        return WarpLinkDeepLink(
            linkId: linkId,
            destination: destination,
            deepLinkUrl: response.deepLinkUrl,
            customParams: response.customParams ?? [:],
            isDeferred: true,
            matchType: response.matchType.flatMap { MatchType(rawValue: $0) },
            matchConfidence: response.matchConfidence,
            matchGuaranteed: response.matchGuaranteed,
            attributionId: response.attributionId,
            matchMethod: response.matchMethod.flatMap { MatchMethod(rawValue: $0) },
            evidenceClass: response.evidenceClass.flatMap { EvidenceClass(rawValue: $0) },
            replayState: response.replayState.flatMap { ReplayState(rawValue: $0) },
            capturedParams: response.capturedParams ?? [:],
            tappedAt: response.tappedAt
        )
    }
}
