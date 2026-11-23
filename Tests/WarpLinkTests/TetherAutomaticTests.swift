import XCTest
@testable import WarpLink

/// The first-launch check in each read mode.
final class TetherAutomaticTests: TetherTestCase {

    private let matchPath = "/attribution/match"

    private func bodies(_ t: InlineTransport) -> [[String: Any]] {
        t.bodies(forPathContaining: matchPath)
    }

    // conformance: WL-S53
    func testPasteButtonModeReadsNothingAtFirstLaunch() throws {
        clipboard.copy(liveCode)
        let t = answering(ReferralWire.matched)
        configure(t, mode: .pasteButton)

        _ = firstOpen()

        XCTAssertEqual(clipboard.readCount, 0)
        XCTAssertNil(try lastMatchBody(t)["tether_code"])
    }

    // conformance: WL-S53
    func testOnCallModeReadsNothingAtFirstLaunch() throws {
        clipboard.copy(liveCode)
        let t = answering(ReferralWire.matched)
        configure(t, mode: .onCall)

        _ = firstOpen()

        XCTAssertEqual(clipboard.readCount, 0)
        XCTAssertNil(try lastMatchBody(t)["tether_code"])
    }

    // conformance: WL-S58
    func testEveryFirstLaunchRequestCarriesTheInstallationId() throws {
        let t = answering(ReferralWire.matched)
        configure(t, mode: .pasteButton)

        _ = firstOpen()

        let body = try lastMatchBody(t)
        XCTAssertEqual(body["installation_id"] as? String, storage.installationId)
        XCTAssertEqual(body["sdk_platform"] as? String, "ios")
    }

    // conformance: WL-S58
    func testAPasteButtonFirstLaunchRequestNamesItsReadModeWithoutAMiss() throws {
        let t = answering(ReferralWire.matched)
        configure(t, mode: .pasteButton)

        _ = firstOpen()

        let body = try lastMatchBody(t)
        XCTAssertEqual(body["tether_read_mode"] as? String, "paste_button")
        XCTAssertNil(body["tether_miss_reason"])
        XCTAssertNil(body["tether_code"])
    }

    // conformance: WL-S58
    func testAnOnCallFirstLaunchRequestNamesItsReadModeWithoutAMiss() throws {
        let t = answering(ReferralWire.matched)
        configure(t, mode: .onCall)

        _ = firstOpen()

        XCTAssertEqual(try lastMatchBody(t)["tether_read_mode"] as? String, "on_call")
    }

    // conformance: WL-S59
    func testAMissLeftByAPasteRidesOnTheNextRequestOnce() throws {
        let t = answering(ReferralWire.matched)
        configure(t, mode: .pasteButton)
        _ = paste("not a code")

        _ = firstOpen()

        let body = try lastMatchBody(t)
        XCTAssertEqual(body["tether_miss_reason"] as? String, "clipboard_empty")
        XCTAssertEqual(body["tether_read_mode"] as? String, "paste_button")
        XCTAssertNil(TetherServices.takeMiss(), "one request carries it, then it is forgotten")
    }

    // conformance: WL-S61
    func testATestCodeIsRepeatedWithoutTheCodeSoTheInstallIsStillChecked() throws {
        clipboard.copy("wl1t_signedbody")
        let t = transport { request in
            let sent = request.resolvedHTTPBody.flatMap { try? JSONSerialization.jsonObject(with: $0) }
            let hasCode = (sent as? [String: Any])?["tether_code"] != nil
            let body = hasCode ? TetherWire.matched(tether: TetherWire.test) : ReferralWire.matched
            return ReferralWire.answer(200, body, for: request)
        }
        configure(t, mode: .automatic)

        let result = firstOpen()

        XCTAssertEqual(bodies(t).count, 2)
        XCTAssertNil(bodies(t).last?["tether_code"])
        XCTAssertNotNil(bodies(t).last?["installation_id"])
        guard case .success(let link?)? = result else { return XCTFail("got \(String(describing: result))") }
        XCTAssertEqual(link.linkId, "link-1")
        XCTAssertEqual(WarpLink.lastTetherTestReceipt, "receipt-1")
        XCTAssertNil(clipboard.text, "cleared as a live code is")
    }

    // conformance: WL-S60
    func testARefusedCodeDoesNotStopTheCascade() throws {
        clipboard.copy(liveCode)
        let t = answering(TetherWire.matched(tether: TetherWire.rejected))
        configure(t, mode: .automatic)

        let result = firstOpen()

        XCTAssertEqual(bodies(t).count, 1, "the server runs the cascade in the same request")
        guard case .success(let link?)? = result else { return XCTFail("got \(String(describing: result))") }
        XCTAssertEqual(link.linkId, "link-1")
        XCTAssertEqual(clipboard.text, liveCode, "a refused code leaves the clipboard alone")
    }

    // conformance: WL-S60
    func testACodeTheServerRefusesWithA4xxIsRepeatedWithoutIt() {
        clipboard.copy(liveCode)
        let t = transport { request in
            let sent = request.resolvedHTTPBody.flatMap { try? JSONSerialization.jsonObject(with: $0) }
            if (sent as? [String: Any])?["tether_code"] != nil {
                return ReferralWire.answer(400, ["error": ["code": "BAD_REQUEST", "message": "x"]], for: request)
            }
            return ReferralWire.answer(200, ReferralWire.matched, for: request)
        }
        configure(t, mode: .automatic)

        let result = firstOpen()

        XCTAssertEqual(bodies(t).count, 2)
        guard case .success(let link?)? = result else { return XCTFail("got \(String(describing: result))") }
        XCTAssertEqual(link.linkId, "link-1")
        XCTAssertEqual(clipboard.clearCount, 0)
    }
}
