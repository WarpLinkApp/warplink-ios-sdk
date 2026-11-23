import XCTest
@testable import WarpLink

/// An estimate reaches `onLink` first in the paste button and on call modes.
/// When the code later resolves an exact link, `onLink` hears it again.
final class TetherLaterExactTests: TetherTestCase {

    private let estimate: [String: Any] = [
        "matched": true,
        "match_type": "probabilistic",
        "match_confidence": 0.77,
        "link_id": "link-estimate",
        "destination_url": "https://example.com/estimate",
        "install_id": "00000000-0000-4000-8000-000000000001",
    ]

    /// An estimate for a request with no code, the exact link for one with a code.
    private func estimateThenExact() -> InlineTransport {
        transport { request in
            let body = String(data: request.resolvedHTTPBody ?? Data(), encoding: .utf8) ?? ""
            let carriesCode = body.contains("tether_code") || body.contains("recovery_token")
            let answer = carriesCode ? TetherWire.matched(tether: TetherWire.accepted) : self.estimate
            return ReferralWire.answer(200, answer, for: request)
        }
    }

    private func read() -> Result<TetherReadResult, WarpLinkError>? {
        let outcome = Box<Result<TetherReadResult, WarpLinkError>>()
        WarpLink.readTether { outcome.value = $0 }
        return outcome.value
    }

    private func linkIds(_ results: Results) -> [String] {
        results.all.compactMap { result in
            guard case let .success(link?) = result else { return nil }
            return link.linkId
        }
    }

    private func lastLink(_ results: Results) -> WarpLinkDeepLink? {
        guard case let .success(link?)? = results.all.last else { return nil }
        return link
    }

    func testAPastedCodeFiresOnLinkAgainWithTheExactLinkAfterTheEstimate() {
        let onLink = Results()
        configure(estimateThenExact(), mode: .pasteButton) { onLink.append($0) }
        WarpLink.runAutoDeferredCheck()
        XCTAssertEqual(linkIds(onLink), ["link-estimate"])
        XCTAssertEqual(lastLink(onLink)?.matchType, .probabilistic)
        clipboard.copy(liveCode)

        guard case .success(let link?)? = paste(liveCode)?.0 else { return XCTFail("not matched") }

        XCTAssertEqual(link.linkId, "link-1")
        XCTAssertEqual(linkIds(onLink), ["link-estimate", "link-1"])
        let exact = lastLink(onLink)
        XCTAssertEqual(exact?.matchType, .deterministic)
        XCTAssertEqual(exact?.evidenceClass, .exact)
        XCTAssertEqual(exact?.matchGuaranteed, true)
    }

    func testReadTetherOnCallFiresOnLinkAgainWithTheExactLink() {
        let onLink = Results()
        configure(estimateThenExact(), mode: .onCall) { onLink.append($0) }
        WarpLink.runAutoDeferredCheck()
        clipboard.copy(liveCode)

        guard case .success(.matched)? = read() else { return XCTFail("not matched") }

        XCTAssertEqual(linkIds(onLink), ["link-estimate", "link-1"])
        XCTAssertEqual(lastLink(onLink)?.matchType, .deterministic)
    }

    func testTheSameExactLinkIsNotHeardTwice() {
        let onLink = Results()
        configure(estimateThenExact(), mode: .onCall) { onLink.append($0) }
        WarpLink.runAutoDeferredCheck()
        clipboard.copy(liveCode)
        _ = read()
        clipboard.copy(liveCode)

        _ = read()

        XCTAssertEqual(linkIds(onLink), ["link-estimate", "link-1"])
    }

    func testEqualLinkIdWithDifferentEvidenceDoesNotFireAgain() {
        let onLink = Results()
        var sameLink = estimate
        sameLink["link_id"] = "link-1"
        let t = transport { request in
            let body = String(data: request.resolvedHTTPBody ?? Data(), encoding: .utf8) ?? ""
            let answer = body.contains("tether_code") ? TetherWire.matched(tether: TetherWire.accepted) : sameLink
            return ReferralWire.answer(200, answer, for: request)
        }
        configure(t, mode: .onCall) { onLink.append($0) }
        WarpLink.runAutoDeferredCheck()
        clipboard.copy(liveCode)

        guard case .success(.matched)? = read() else { return XCTFail("not matched") }

        XCTAssertEqual(linkIds(onLink), ["link-1"], "the same link is not routed again for stronger evidence")
    }

    func testAnEstimateOnLinkNeverHeardIsNotReplaced() {
        let onLink = Results()
        configure(estimateThenExact(), mode: .onCall) { onLink.append($0) }
        _ = firstOpen()
        clipboard.copy(liveCode)

        guard case .success(.matched)? = read() else { return XCTFail("not matched") }

        XCTAssertTrue(linkIds(onLink).isEmpty, "a manual check never reached onLink, so nothing was replaced")
    }

    func testRedeemInvitationDoesNotFireOnLinkAgain() {
        let onLink = Results()
        configure(estimateThenExact(), mode: .pasteButton) { onLink.append($0) }
        WarpLink.runAutoDeferredCheck()

        let result = redeem(liveToken)

        guard case .success(let link?)? = result else { return XCTFail("got \(String(describing: result))") }
        XCTAssertEqual(link.linkId, "link-1")
        XCTAssertEqual(linkIds(onLink), ["link-estimate"], "redeemInvitation answers its own caller only")
    }

    private func staleLink() -> WarpLinkDeepLink {
        WarpLinkDeepLink(
            linkId: "stale", destination: "https://example.com/stale", deepLinkUrl: nil,
            customParams: [:], isDeferred: true, matchType: .deterministic, matchConfidence: 1
        )
    }

    func testAClearBeforeTheDispatchKeepsAStaleLinkOutOfOnLinkAndTheRecord() {
        let onLink = Results()
        let store = configure(estimateThenExact(), mode: .onCall) { onLink.append($0) }
        let before = store.attributionClearGeneration

        store.clearAll()
        WarpLink.dispatchAttributionToOnLink(.success(staleLink()), ifGeneration: before)

        XCTAssertTrue(linkIds(onLink).isEmpty, "a link read before clearAll is not sent")
        XCTAssertNil(store.onLinkDeliveredRoute, "and it does not restore the record")
    }

    func testAClearAfterTheRecordButBeforeTheCallbackRunsKeepsTheLinkFromOnLink() {
        let onLink = Results()
        let store = configure(estimateThenExact(), mode: .onCall) { onLink.append($0) }
        let queued = Box<[() -> Void]>()
        queued.value = []
        SDKEnvironment.deliver = { work in queued.value?.append(work) }

        WarpLink.dispatchAttributionToOnLink(.success(staleLink()), ifGeneration: store.attributionClearGeneration)
        XCTAssertEqual(queued.value?.count, 1, "the callback is queued, not yet run")
        XCTAssertEqual(store.onLinkDeliveredRoute, staleLink().routeIdentity)

        store.clearAttribution()
        queued.value?.forEach { $0() }

        XCTAssertTrue(linkIds(onLink).isEmpty, "the callback rechecks the generation before onLink")
        XCTAssertNil(store.onLinkDeliveredRoute)
    }

    func testAClearWhileTheFirstLaunchCheckRunsKeepsItsLinkFromOnLink() {
        let onLink = Results()
        let holder = Box<Storage>()
        let t = transport { request in
            holder.value?.clearAttribution()
            return ReferralWire.answer(200, self.estimate, for: request)
        }
        holder.value = configure(t, mode: .pasteButton) { onLink.append($0) }

        WarpLink.runAutoDeferredCheck()

        XCTAssertTrue(linkIds(onLink).isEmpty, "the check read its link before the clear, so onLink never hears it")
        XCTAssertNil(holder.value?.onLinkDeliveredRoute)
    }

    func testTheDeliveredLinkSurvivesALaunchAndIsForgottenByClearAttribution() {
        let onLink = Results()
        let store = configure(estimateThenExact(), mode: .onCall) { onLink.append($0) }
        WarpLink.runAutoDeferredCheck()
        let stored = store.onLinkDeliveredRoute
        XCTAssertNotNil(stored)

        let relaunched = Storage(
            defaults: store.defaults,
            markerStore: InMemoryMarkerStore(),
            installMarkerStore: InMemoryMarkerStore()
        )
        XCTAssertEqual(relaunched.onLinkDeliveredRoute, stored)

        store.clearAttribution()
        XCTAssertNil(store.onLinkDeliveredRoute)
    }

    func testACodeWithNoEarlierLinkDoesNotFireOnLink() {
        let onLink = Results()
        let t = transport { request in
            let body = String(data: request.resolvedHTTPBody ?? Data(), encoding: .utf8) ?? ""
            let answer = body.contains("tether_code") ? TetherWire.matched(tether: TetherWire.accepted) : ["matched": false]
            return ReferralWire.answer(200, answer, for: request)
        }
        configure(t, mode: .onCall) { onLink.append($0) }
        WarpLink.runAutoDeferredCheck()
        clipboard.copy(liveCode)

        guard case .success(.matched)? = read() else { return XCTFail("not matched") }

        XCTAssertTrue(linkIds(onLink).isEmpty, "the exact link reaches the read callback only")
    }

    func testAutomaticModeSendsTheCodeWithTheFirstRequestAndFiresOnLinkOnce() {
        let onLink = Results()
        clipboard.copy(liveCode)
        configure(estimateThenExact(), mode: .automatic) { onLink.append($0) }

        WarpLink.runAutoDeferredCheck()

        XCTAssertEqual(linkIds(onLink), ["link-1"])
        XCTAssertEqual(lastLink(onLink)?.matchType, .deterministic)
    }
}
