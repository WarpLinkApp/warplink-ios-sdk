import XCTest
@testable import WarpLink

/// A `pending` Tether answer is not final, and a rate limit is not a refusal.
final class TetherPendingTests: TetherTestCase {

    private let matchPath = "/attribution/match"

    private func pending(after seconds: Int?) -> [String: Any] {
        var tether: [String: Any] = ["status": "pending", "accepted": false]
        if let seconds = seconds { tether["retry_after_seconds"] = seconds }
        return ["matched": false, "tether": tether]
    }

    private func hasCode(_ request: URLRequest) -> Bool {
        let sent = request.resolvedHTTPBody.flatMap { try? JSONSerialization.jsonObject(with: $0) }
        return (sent as? [String: Any])?["tether_code"] != nil
    }

    private func recorderInstalled() -> ScheduleRecorder {
        let recorder = ScheduleRecorder()
        recorder.install()
        return recorder
    }

    // conformance: WL-S62
    func testAPendingAnswerWaitsTheServersHintThenSendsTheSameRequestOnce() throws {
        clipboard.copy(liveCode)
        var calls = 0
        let t = transport { request in
            calls += 1
            let body = calls == 1 ? self.pending(after: 7) : TetherWire.matched(tether: TetherWire.accepted)
            return ReferralWire.answer(200, body, for: request)
        }
        configure(t, mode: .automatic)
        let recorder = recorderInstalled()

        let result = firstOpen()

        let bodies = t.bodies(forPathContaining: matchPath)
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies.last?["tether_code"] as? String, liveCode)
        XCTAssertEqual(recorder.delays, [7.0])
        guard case .success(let link?)? = result else { return XCTFail("got \(String(describing: result))") }
        XCTAssertEqual(link.linkId, "link-1")
        XCTAssertNil(clipboard.text, "cleared once the server accepted the code")
    }

    // conformance: WL-S62
    func testTheWaitIsCapped() {
        clipboard.copy(liveCode)
        let t = answering(pending(after: 600))
        configure(t, mode: .automatic)
        let recorder = recorderInstalled()

        _ = firstOpen()

        XCTAssertEqual(recorder.delays, [TetherPending.maxWait])
    }

    func testAPendingAnswerWithNoHintWaitsTheDefault() {
        clipboard.copy(liveCode)
        let t = answering(pending(after: nil))
        configure(t, mode: .automatic)
        let recorder = recorderInstalled()

        _ = firstOpen()

        XCTAssertEqual(recorder.delays, [TetherPending.defaultWait])
    }

    // conformance: WL-S62
    func testAnAnswerThatStaysPendingIsRetriedOnceAndKeepsAttributionOpen() {
        clipboard.copy(liveCode)
        let t = answering(pending(after: 5))
        configure(t, mode: .automatic)
        _ = recorderInstalled()

        let result = firstOpen()

        XCTAssertEqual(t.bodies(forPathContaining: matchPath).count, 2)
        guard case .success(nil)? = result else { return XCTFail("got \(String(describing: result))") }
        XCTAssertFalse(WarpLink.isAttributionComplete, "the next launch asks again")
        XCTAssertEqual(clipboard.text, liveCode, "the code stays for that next ask")
    }

    // conformance: WL-S62
    func testAPastedCodeThatIsPendingRetriesOnceAndSettlesItsRecord() throws {
        var calls = 0
        let t = transport { request in
            calls += 1
            let body = calls == 1 ? self.pending(after: 3) : TetherWire.matched(tether: TetherWire.accepted)
            return ReferralWire.answer(200, body, for: request)
        }
        configure(t, mode: .pasteButton)
        let recorder = recorderInstalled()

        let outcome = paste(liveCode)

        XCTAssertEqual(t.bodies(forPathContaining: matchPath).count, 2)
        XCTAssertEqual(recorder.delays, [3.0])
        guard case .success(let link?)? = outcome?.0 else { return XCTFail("got \(String(describing: outcome))") }
        XCTAssertEqual(link.linkId, "link-1")
        XCTAssertNil(ReferralServices.pendingStore.load(), "settled once the retry was answered")
    }

    // conformance: WL-S62
    func testAPastedCodeThatStaysPendingKeepsItsRecordForTheNextLaunch() {
        let t = answering(pending(after: 3))
        configure(t, mode: .pasteButton)
        _ = recorderInstalled()

        _ = paste(liveCode)

        XCTAssertEqual(t.bodies(forPathContaining: matchPath).count, 2)
        XCTAssertNotNil(ReferralServices.pendingStore.load())
    }

    func testARateLimitedCodeIsNotResentWithoutIt() {
        clipboard.copy(liveCode)
        let t = transport { request in
            self.hasCode(request)
                ? ReferralWire.answer(429, ["error": ["code": "RATE_LIMITED", "message": "x"]], for: request)
                : ReferralWire.answer(200, ReferralWire.matched, for: request)
        }
        configure(t, mode: .automatic)
        _ = recorderInstalled()

        let result = firstOpen()

        let bodies = t.bodies(forPathContaining: matchPath)
        XCTAssertFalse(bodies.isEmpty)
        XCTAssertTrue(bodies.allSatisfy { $0["tether_code"] as? String == liveCode })
        guard case .failure(.serverError(429, _))? = result else { return XCTFail("got \(String(describing: result))") }
        XCTAssertEqual(clipboard.clearCount, 0)
    }

    func testTheRequestWithoutTheCodeKeepsTheReadModeAndTheMissReason() {
        let fields = TetherRequestFields(
            installationId: "id-1",
            claim: TetherClaim(code: .live("body"), changeCount: 1),
            readMode: .automatic,
            missReason: .clipboardEmpty
        )

        let again = fields.withoutCode()

        XCTAssertNil(again.code)
        XCTAssertEqual(again.installationId, "id-1")
        XCTAssertEqual(again.readMode, .automatic)
        XCTAssertEqual(again.missReason, .clipboardEmpty)
    }
}
