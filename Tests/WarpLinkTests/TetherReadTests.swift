import XCTest
@testable import WarpLink

/// `readTether()`, and what clears a kept miss or receipt.
final class TetherReadTests: TetherTestCase {

    private let matchPath = "/attribution/match"

    private func read() -> Result<TetherReadResult, WarpLinkError>? {
        let outcome = Box<Result<TetherReadResult, WarpLinkError>>()
        WarpLink.readTether { outcome.value = $0 }
        return outcome.value
    }

    // conformance: WL-S53
    func testReadTetherReadsOnlyWhenCalledInOnCallMode() throws {
        clipboard.copy(liveCode)
        let t = answering(TetherWire.matched(tether: TetherWire.accepted))
        configure(t, mode: .onCall)
        _ = firstOpen()
        XCTAssertEqual(clipboard.readCount, 0)

        let result = read()

        XCTAssertEqual(clipboard.readCount, 1)
        guard case .success(.matched(let link))? = result else { return XCTFail("got \(String(describing: result))") }
        XCTAssertEqual(link.linkId, "link-1")
        XCTAssertEqual(try lastMatchBody(t)["tether_read_mode"] as? String, "on_call")
        XCTAssertNil(clipboard.text)
    }

    // conformance: WL-S53
    func testReadTetherWorksInPasteButtonMode() {
        clipboard.copy(liveCode)
        configure(answering(TetherWire.matched(tether: TetherWire.accepted)), mode: .pasteButton)

        guard case .success(.matched)? = read() else { return XCTFail("not matched") }
    }

    // conformance: WL-S53
    func testReadTetherWorksInAutomaticMode() {
        clipboard.copy(liveCode)
        configure(answering(TetherWire.matched(tether: TetherWire.accepted)), mode: .automatic)

        guard case .success(.matched)? = read() else { return XCTFail("not matched") }
    }

    // conformance: WL-S59
    func testReadTetherWithNothingUsableReportsWhyAndSendsNothing() {
        let t = answering(ReferralWire.matched)
        configure(t, mode: .onCall)

        let result = read()

        guard case .success(.noCode(.clipboardEmpty))? = result else { return XCTFail("got \(String(describing: result))") }
        XCTAssertEqual(t.requestCount(forPathContaining: matchPath), 0)
        XCTAssertEqual(TetherServices.takeMiss()?.mode, .onCall)
    }

    // conformance: WL-S59
    func testAnOwnReadThatTheSystemRefusesReportsPasteNotAllowed() {
        clipboard.copy(liveCode)
        clipboard.denied = true
        configure(answering(ReferralWire.matched), mode: .onCall)

        guard case .success(.noCode(.pasteNotAllowed))? = read() else { return XCTFail("not a miss") }
    }

    // conformance: WL-S61
    func testReadTetherReturnsTheReceiptOfATestCode() {
        clipboard.copy("wl1t_signedbody")
        configure(answering(TetherWire.matched(tether: TetherWire.test)), mode: .onCall)

        guard case .success(.test(receipt: "receipt-1"))? = read() else { return XCTFail("not a test") }
        XCTAssertNil(clipboard.text)
    }

    // conformance: WL-S60
    func testAnotherMethodsLinkIsReturnedWhenTheCodeIsRefused() {
        clipboard.copy(liveCode)
        configure(answering(TetherWire.matched(tether: TetherWire.rejected)), mode: .onCall)

        guard case .success(.matched)? = read() else { return XCTFail("the cascade still matched") }
        XCTAssertEqual(clipboard.text, liveCode)
    }

    // conformance: WL-S60
    func testACodeThatLeadsNowhereIsUnusableAndLeavesTheClipboard() {
        clipboard.copy(liveCode)
        let none = TetherWire.matched(tether: TetherWire.notFound).merging(["matched": false]) { _, new in new }
        configure(answering(none), mode: .onCall)

        guard case .success(.unusable)? = read() else { return XCTFail("not unusable") }
        XCTAssertEqual(clipboard.text, liveCode)
    }

    func testReadTetherBeforeConfigureFails() {
        SDKEnvironment.deliver = { work in work() }
        guard case .failure(.notConfigured)? = read() else { return XCTFail("not notConfigured") }
    }

    // conformance: WL-S58
    func testClearAttributionForgetsTheMissTheReceiptAndTheInstallationId() {
        let suite = "TetherReadTests-clear"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let device = InMemoryMarkerStore()
        let install = InMemoryMarkerStore()
        makeSDKSynchronous(answering(ReferralWire.matched))
        SDKEnvironment.makeStorage = { environment in
            Storage(
                environment: environment, defaults: defaults,
                markerStore: device, installMarkerStore: install
            )
        }
        WarpLink.configure(
            apiKey: "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
            options: WarpLinkOptions(autoDeferredCheck: false)
        )
        let before = WarpLink.storage?.installationId
        TetherServices.recordMiss(.expired, mode: .automatic)
        TetherServices.recordTestReceipt("receipt-1")

        guard case .success = WarpLink.clearAttribution() else { return XCTFail("clear failed") }
        XCTAssertNil(TetherServices.takeMiss())
        XCTAssertNil(WarpLink.lastTetherTestReceipt)
        XCTAssertNotEqual(WarpLink.storage?.installationId, before)
        defaults.removePersistentDomain(forName: suite)
    }

    func testReconfiguringForgetsAKeptMissAndReceipt() {
        configure(answering(ReferralWire.matched), mode: .pasteButton)
        TetherServices.recordMiss(.expired, mode: .automatic)
        TetherServices.recordTestReceipt("receipt-1")

        configure(answering(ReferralWire.matched), mode: .onCall)

        XCTAssertNil(TetherServices.takeMiss())
        XCTAssertNil(WarpLink.lastTetherTestReceipt)
    }

    // conformance: WL-S57
    func testTheSystemClipboardMatchesThePlatform() {
        let system = makeSystemClipboard()
        #if !canImport(UIKit)
        XCTAssertFalse(system.canRead)
        XCTAssertTrue(system is NoClipboard)
        #else
        XCTAssertTrue(system.canRead)
        #endif
    }
}
