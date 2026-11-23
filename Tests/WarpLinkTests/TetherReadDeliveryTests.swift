import XCTest
@testable import WarpLink

/// `readTether()` answers on the main queue on every path, even when the
/// clipboard read runs off it, and takes only `wl1_` and `wl1t_` text.
final class TetherReadDeliveryTests: TetherTestCase {

    /// Reads with the shipping delivery and a read queue that is not main.
    /// Returns where the completion ran, and what it carried.
    private func readOffMain() -> (onMain: Bool, result: Result<TetherReadResult, WarpLinkError>)? {
        SDKEnvironment.deliver = { work in DispatchQueue.main.async(execute: work) }
        TetherServices.readQueue = { work in DispatchQueue.global().async(execute: work) }
        let done = expectation(description: "completion")
        var seen: (Bool, Result<TetherReadResult, WarpLinkError>)?
        WarpLink.readTether { result in
            seen = (Thread.isMainThread, result)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return seen.map { (onMain: $0.0, result: $0.1) }
    }

    func testAMissIsDeliveredOnMain() throws {
        configure(answering(ReferralWire.matched), mode: .onCall)

        let seen = try XCTUnwrap(readOffMain())

        XCTAssertTrue(seen.onMain)
        guard case .success(.noCode) = seen.result else { return XCTFail("got \(seen.result)") }
    }

    func testAnExpiredCodeIsDeliveredOnMain() throws {
        clipboard.copy(liveCode)
        let t = answering(ReferralWire.matched)
        configure(t, mode: .onCall)
        now = Date(timeIntervalSince1970: 1_950_000_000)

        let seen = try XCTUnwrap(readOffMain())

        XCTAssertTrue(seen.onMain)
        XCTAssertEqual(t.requestCount(forPathContaining: "/attribution/match"), 0, "\(seen.result)")
    }

    func testAMatchIsDeliveredOnMain() throws {
        clipboard.copy(liveCode)
        configure(answering(TetherWire.matched(tether: TetherWire.accepted)), mode: .onCall)

        let seen = try XCTUnwrap(readOffMain())

        XCTAssertTrue(seen.onMain)
        guard case .success(.matched) = seen.result else { return XCTFail("got \(seen.result)") }
    }

    func testReadingBeforeConfigureIsDeliveredOnMain() throws {
        let seen = try XCTUnwrap(readOffMain())

        XCTAssertTrue(seen.onMain)
        guard case .failure(.notConfigured) = seen.result else { return XCTFail("got \(seen.result)") }
    }

    // conformance: WL-S54
    func testAnUnprefixedTokenOnTheClipboardIsNotACode() {
        clipboard.copy(liveToken)
        let t = answering(ReferralWire.matched)
        configure(t, mode: .onCall)
        var outcome: Result<TetherReadResult, WarpLinkError>?

        WarpLink.readTether { outcome = $0 }

        guard case .success(.noCode(.clipboardEmpty))? = outcome else { return XCTFail("got \(String(describing: outcome))") }
        XCTAssertEqual(t.requestCount(forPathContaining: "/attribution/match"), 0)
        XCTAssertEqual(clipboard.clearCount, 0)
    }
}
