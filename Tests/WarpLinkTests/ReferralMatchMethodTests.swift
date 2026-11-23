import XCTest
@testable import WarpLink

/// The server names the install referrer match `referrer`. Older rows say `android_referrer`.
final class ReferralMatchMethodTests: XCTestCase {

    private func decode(_ method: String) throws -> WarpLinkDeepLink {
        let json = #"{"linkId":"l","destination":"https://e.com","matchMethod":"\#(method)"}"#
        return try JSONDecoder().decode(WarpLinkDeepLink.self, from: Data(json.utf8))
    }

    // conformance: WL-S46
    func testReferrerAndAndroidReferrerReadAsTheSameMethod() {
        XCTAssertEqual(MatchMethod(rawValue: "referrer"), .androidReferrer)
        XCTAssertEqual(MatchMethod(rawValue: "android_referrer"), .androidReferrer)
    }

    // conformance: WL-S46
    func testAnUnknownMethodStillReadsAsNil() {
        XCTAssertNil(MatchMethod(rawValue: "referrers"))
        XCTAssertNil(MatchMethod(rawValue: ""))
    }

    // conformance: WL-S46
    func testACachedMatchAnsweredWithReferrerKeepsItsMethod() throws {
        XCTAssertEqual(try decode("referrer").matchMethod, .androidReferrer)
        XCTAssertEqual(try decode("android_referrer").matchMethod, .androidReferrer)
    }

    // conformance: WL-S46
    func testEveryKnownMethodStillRoundTripsItsRawValue() {
        let all: [MatchMethod] = [.installToken, .androidReferrer, .deviceId, .linkOpen, .probabilistic]

        for method in all {
            XCTAssertEqual(MatchMethod(rawValue: method.rawValue), method)
        }
    }
}
