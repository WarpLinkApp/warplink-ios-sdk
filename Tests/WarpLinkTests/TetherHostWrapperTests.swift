import XCTest
@_spi(ReactNative) @_spi(Flutter) @testable import WarpLink

/// A cross-platform SDK names itself, and the request reports that name.
final class TetherHostWrapperTests: TetherTestCase {

    private func platform() -> String? {
        var body: [String: Any] = [:]
        TetherRequestFields(installationId: "id-1").write(to: &body)
        return body["sdk_platform"] as? String
    }

    // conformance: WL-S58
    func testAnAppWithNoWrapperReportsIos() {
        XCTAssertEqual(platform(), "ios")
    }

    // conformance: WL-S58
    func testTheReactNativeBridgeReportsReactNative() {
        WarpLink.declareHostWrapper("react-native")
        XCTAssertEqual(platform(), "react-native")
    }

    // conformance: WL-S58
    func testTheFlutterPluginReportsFlutter() {
        WarpLink.declareHostWrapper("flutter")
        XCTAssertEqual(platform(), "flutter")
    }

    func testAnUnknownWrapperNameIsIgnored() {
        WarpLink.declareHostWrapper("react-native")
        WarpLink.declareHostWrapper("unity")
        XCTAssertEqual(platform(), "react-native")
    }

    func testAMatchRequestFromAWrapperCarriesItsName() throws {
        WarpLink.declareHostWrapper("flutter")
        let t = answering(ReferralWire.matched)
        configure(t, mode: .pasteButton)

        _ = firstOpen()

        XCTAssertEqual(try lastMatchBody(t)["sdk_platform"] as? String, "flutter")
    }
}
