import XCTest
@testable import WarpLink

/// A deferred check, automatic or manual, starts only while the app is in the
/// foreground. A call made earlier waits and then runs; it is never refused.
final class ForegroundWaitTests: CheckTrafficTestCase {

    /// The app's foreground state, driven by the test.
    private final class Foreground {
        private(set) var waiting: [() -> Void] = []

        func install() {
            SDKEnvironment.whenActive = { [self] work in waiting.append(work) }
        }

        func activate() {
            let pending = waiting
            waiting = []
            pending.forEach { $0() }
        }
    }

    private func inactiveApp() -> Foreground {
        let foreground = Foreground()
        foreground.install()
        return foreground
    }

    // conformance: WL-S71

    func testACheckCalledWhileInactiveSendsNothingUntilActivation() {
        let transport = serving(CheckWire.matched)
        configure(transport)
        let foreground = inactiveApp()
        let results = Results()

        WarpLink.checkDeferredDeepLink { results.append($0) }

        XCTAssertEqual(matchCount(transport), 0)
        XCTAssertTrue(results.all.isEmpty, "the call waits; it does not fail")

        foreground.activate()

        XCTAssertEqual(matchCount(transport), 1)
        guard case .success(let link?)? = results.all.first else {
            return XCTFail("expected the link after activation, got \(String(describing: results.all.first))")
        }
        XCTAssertEqual(link.linkId, "link-deferred-1")
    }

    // conformance: WL-S71

    func testTheAutomaticCheckWaitsToo() {
        let transport = serving(CheckWire.noMatch)
        let foreground = inactiveApp()
        configure(transport, options: WarpLinkOptions())

        XCTAssertEqual(matchCount(transport), 0)
        foreground.activate()
        XCTAssertEqual(matchCount(transport), 1)
    }

    func testASecondCallWhileWaitingJoinsTheSameCheck() {
        let transport = serving(CheckWire.matched)
        configure(transport)
        let foreground = inactiveApp()
        let first = Results()
        let second = Results()

        WarpLink.checkDeferredDeepLink { first.append($0) }
        WarpLink.checkDeferredDeepLink { second.append($0) }
        foreground.activate()

        XCTAssertEqual(matchCount(transport), 1)
        XCTAssertEqual(first.all.count, 1)
        XCTAssertEqual(second.all.count, 1)
    }

    // conformance: WL-S71

    func testAnActiveAppSendsAtOnce() {
        let transport = serving(CheckWire.noMatch)
        configure(transport)

        check()

        XCTAssertEqual(matchCount(transport), 1)
    }

    func testASkipDoesNotWaitForTheForeground() {
        let transport = serving(CheckWire.matched)
        configure(transport)
        installedAt = clock.addingTimeInterval(-40 * day)
        _ = inactiveApp()

        assertNoMatch(check())
    }

    func testAnInstallThatGrewTooOldDuringTheWaitSendsNothing() {
        let transport = serving(CheckWire.matched)
        configure(transport)
        let foreground = inactiveApp()
        let results = Results()
        WarpLink.checkDeferredDeepLink { results.append($0) }

        clock.addTimeInterval(31 * day)
        foreground.activate()

        XCTAssertEqual(matchCount(transport), 0)
        assertNoMatch(results.all.first)
        XCTAssertFalse(storage.isAttributionComplete)
        XCTAssertEqual(storage.attemptNumber, 0)
    }

    func testAFailureCountedDuringTheWaitMakesTheCheckSendNothing() {
        let transport = serving(CheckWire.matched)
        configure(transport)
        let foreground = inactiveApp()
        let results = Results()
        WarpLink.checkDeferredDeepLink { results.append($0) }

        storage.recordCheckFailure(at: clock)
        foreground.activate()

        XCTAssertEqual(matchCount(transport), 0)
        assertNoMatch(results.all.first)
        XCTAssertEqual(storage.checkBackoff?.failures, 1, "the skip adds no failure")
    }

    func testACheckWaitingWhenTheSessionIsRebuiltAnswersNoMatchAndSendsNothing() {
        let transport = serving(CheckWire.matched)
        configure(transport)
        let foreground = inactiveApp()
        let results = Results()
        WarpLink.checkDeferredDeepLink { results.append($0) }

        WarpLink.configure(
            apiKey: liveKey, options: WarpLinkOptions(debugLogging: true, autoDeferredCheck: false)
        )
        foreground.activate()

        XCTAssertEqual(matchCount(transport), 0, "an abandoned check never sends")
        assertNoMatch(results.all.first)
    }

    func testTheAttemptNumberIsTakenWhenTheRequestIsSent() {
        let transport = serving(CheckWire.noMatch)
        configure(transport)
        let foreground = inactiveApp()

        WarpLink.checkDeferredDeepLink { _ in }
        XCTAssertEqual(storage.attemptNumber, 0)
        foreground.activate()

        XCTAssertEqual(storage.attemptNumber, 1)
    }
}
