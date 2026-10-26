import XCTest
@testable import WarpLink

final class ReferralResultFieldsTests: XCTestCase {

    private func decode(_ json: String) throws -> WarpLinkDeepLink {
        try JSONDecoder().decode(WarpLinkDeepLink.self, from: Data(json.utf8))
    }

    // conformance: WL-S43
    func testAPayloadCachedByAnOlderSDKDecodesWithSafeDefaults() throws {
        let link = try decode(#"{"linkId":"l","destination":"https://e.com","isDeferred":true}"#)

        XCTAssertNil(link.attributionId)
        XCTAssertNil(link.matchMethod)
        XCTAssertNil(link.evidenceClass)
        XCTAssertNil(link.replayState)
        XCTAssertTrue(link.capturedParams.isEmpty)
        XCTAssertNil(link.tappedAt)
    }

    // conformance: WL-S43
    func testAValueTheSDKDoesNotKnowDoesNotLoseTheCachedMatch() throws {
        let link = try decode("""
        {"linkId":"l","destination":"https://e.com","matchMethod":"quantum","evidenceClass":"vibes",
         "replayState":"later","attributionId":"a-1"}
        """)

        XCTAssertEqual(link.linkId, "l")
        XCTAssertEqual(link.attributionId, "a-1")
        XCTAssertNil(link.matchMethod)
        XCTAssertNil(link.evidenceClass)
        XCTAssertNil(link.replayState)
    }

    func testTheEvidenceFieldsSurviveTheCacheRoundTrip() throws {
        let link = WarpLinkDeepLink(
            linkId: "l", destination: "https://e.com", attributionId: "a-1",
            matchMethod: .linkOpen, evidenceClass: .legacyLink, replayState: .replayed,
            capturedParams: ["utm_source": .string("friend")], tappedAt: "2026-10-20T10:00:00.000Z"
        )

        let back = try JSONDecoder().decode(WarpLinkDeepLink.self, from: JSONEncoder().encode(link))

        XCTAssertEqual(back, link)
    }

    // conformance: WL-S46
    func testALegacyLinkIdMatchStaysDistinctFromATokenBackedOne() throws {
        let legacy = try XCTUnwrap(ReferralMatch.deepLink(from: response(method: "link_open", evidence: "legacy_link")))
        let token = try XCTUnwrap(ReferralMatch.deepLink(from: response(method: "install_token", evidence: "exact")))

        XCTAssertEqual(legacy.evidenceClass, .legacyLink)
        XCTAssertEqual(legacy.matchMethod, .linkOpen)
        XCTAssertEqual(token.evidenceClass, .exact)
        XCTAssertEqual(token.matchMethod, .installToken)
        XCTAssertNotEqual(legacy.evidenceClass, token.evidenceClass)
    }

    func testAnOlderServerAnswerMapsToNilEvidence() throws {
        let link = try XCTUnwrap(ReferralMatch.deepLink(from: response(method: nil, evidence: nil)))

        XCTAssertNil(link.matchMethod)
        XCTAssertNil(link.evidenceClass)
        XCTAssertNil(link.attributionId)
        XCTAssertTrue(link.isDeferred)
    }

    private func response(method: String?, evidence: String?) -> AttributionResponse {
        var json = ReferralWire.matched
        json["match_method"] = method
        json["evidence_class"] = evidence
        if method == nil { json["attribution_id"] = nil }
        let data = try! JSONSerialization.data(withJSONObject: json.compactMapValues { $0 })
        guard case let .success(decoded) = AttributionResponse.decode(data: data) else {
            preconditionFailure("fixture must decode")
        }
        return decoded
    }
}
