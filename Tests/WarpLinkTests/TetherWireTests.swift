import XCTest
@testable import WarpLink

/// What Tether puts on the wire and reads back.
final class TetherWireTests: XCTestCase {

    private let id = "6f1c1f0e-5a0e-4f3e-9d5b-0a1f1d3c9b11"

    private func written(_ fields: TetherRequestFields) -> [String: Any] {
        var body: [String: Any] = [:]
        fields.write(to: &body)
        return body
    }

    // conformance: WL-S58
    func testEveryRequestCarriesTheInstallationIdAndPlatform() {
        let body = written(TetherRequestFields(installationId: id))
        XCTAssertEqual(body["installation_id"] as? String, id)
        XCTAssertEqual(body["sdk_platform"] as? String, "ios")
    }

    // conformance: WL-S54
    func testAnEmptyReadSendsNoCodeAndNoReport() {
        let body = written(TetherRequestFields(installationId: id))
        for key in ["tether_code", "tether_read_mode", "tether_miss_reason", "recovery_token"] {
            XCTAssertNil(body[key], key)
        }
    }

    // conformance: WL-S54
    func testALiveCodeTravelsAsTetherCodeOnly() {
        let claim = TetherClaim(code: .live("wl1_abc"), changeCount: 3)
        let body = written(TetherRequestFields(installationId: id, claim: claim, readMode: .automatic))
        XCTAssertEqual(body["tether_code"] as? String, "wl1_abc")
        XCTAssertEqual(body["tether_read_mode"] as? String, "automatic")
        XCTAssertNil(body["recovery_token"])
    }

    // conformance: WL-S61
    func testATestCodeIsSentLikeALiveCode() {
        let claim = TetherClaim(code: .test("wl1t_abc"), changeCount: 3)
        let body = written(TetherRequestFields(installationId: id, claim: claim, readMode: .onCall))
        XCTAssertEqual(body["tether_code"] as? String, "wl1t_abc")
        XCTAssertEqual(body["tether_read_mode"] as? String, "on_call")
    }

    func testAnInvitationStillTravelsAsRecoveryToken() {
        let claim = TetherClaim(code: .invitation("raw-token"), changeCount: nil)
        let body = written(TetherRequestFields(installationId: id, claim: claim, readMode: .pasteButton))
        XCTAssertEqual(body["recovery_token"] as? String, "raw-token")
        XCTAssertNil(body["tether_code"])
    }

    // conformance: WL-S59
    func testAMissSendsItsReasonAndTheReadMode() {
        let fields = TetherRequestFields(
            installationId: id, readMode: .automatic, missReason: .pasteNotAllowed
        )
        let body = written(fields)
        XCTAssertEqual(body["tether_miss_reason"] as? String, "paste_not_allowed")
        XCTAssertEqual(body["tether_read_mode"] as? String, "automatic")
    }

    func testTheSameRequestWithoutTheCodeKeepsTheReadModeAndTheMissReason() {
        let claim = TetherClaim(code: .live("wl1_abc"), changeCount: 3)
        let fields = TetherRequestFields(
            installationId: id, claim: claim, readMode: .automatic, missReason: .expired
        )
        let body = written(fields.withoutCode())
        XCTAssertEqual(body["installation_id"] as? String, id)
        XCTAssertNil(body["tether_code"])
        XCTAssertEqual(body["tether_read_mode"] as? String, "automatic")
        XCTAssertEqual(body["tether_miss_reason"] as? String, "expired")
    }

    func testTheNamesTheServerRecordsAreTheRawValues() {
        XCTAssertEqual(
            Set(TetherReadMode.allCases.map(\.rawValue)), ["paste_button", "automatic", "on_call"]
        )
        XCTAssertEqual(Set(TetherMissReason.allCases.map(\.rawValue)), [
            "paste_not_allowed", "clipboard_empty", "in_app_browser", "expired",
            "other_app", "link_ended", "older_sdk",
        ])
    }

    func testTheResponseObjectIsDecoded() throws {
        let json: [String: Any] = ["status": "test", "accepted": false, "test": true, "test_receipt": "r-1"]
        let tether = try XCTUnwrap(TetherResponse(json: json))
        XCTAssertEqual(tether, TetherResponse(status: "test", accepted: false, test: true, testReceipt: "r-1"))
    }

    func testAMissingFlagReadsAsFalseAndAReceiptAsNil() throws {
        let tether = try XCTUnwrap(TetherResponse(json: ["status": "not_found"]))
        XCTAssertFalse(tether.accepted)
        XCTAssertFalse(tether.test)
        XCTAssertNil(tether.testReceipt)
    }

    func testAnswerWithoutAStatusIsNoAnswer() {
        XCTAssertNil(TetherResponse(json: nil))
        XCTAssertNil(TetherResponse(json: "accepted"))
        XCTAssertNil(TetherResponse(json: ["accepted": true]))
    }

    func testAMatchAnswerCarriesTheTetherObject() throws {
        let data = try JSONSerialization.data(withJSONObject: TetherWire.matched(tether: TetherWire.accepted))
        let response = try AttributionResponse.decode(data: data).get()
        XCTAssertEqual(response.tether?.status, "accepted")
        XCTAssertEqual(response.tether?.accepted, true)
    }

    func testAnAnswerFromAServerWithoutTetherHasNone() throws {
        let data = try JSONSerialization.data(withJSONObject: ReferralWire.matched)
        XCTAssertNil(try AttributionResponse.decode(data: data).get().tether)
    }
}
