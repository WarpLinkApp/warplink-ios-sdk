import XCTest
@testable import WarpLink

/// The gate closes when the 200 answer is decoded, on the network queue, and
/// not after the hop to the main queue that hands the result to the app.
final class GateBeforeDeliveryTests: CheckTrafficTestCase {

    /// Main-queue work the SDK asked for, held until the test runs it.
    private final class HeldDelivery {
        var queued: [() -> Void] = []

        func install() {
            SDKEnvironment.deliver = { [self] work in queued.append(work) }
        }

        func drain() {
            while !queued.isEmpty { queued.removeFirst()() }
        }
    }

    // conformance: WL-S68

    func testTheGateIsClosedBeforeTheResultReachesTheMainQueue() {
        configure(serving(CheckWire.matched))
        let held = HeldDelivery()
        held.install()
        let results = Results()

        WarpLink.checkDeferredDeepLink { results.append($0) }

        XCTAssertFalse(held.queued.isEmpty, "the answer is still waiting for the main queue")
        XCTAssertTrue(results.all.isEmpty, "the app has not been told yet")
        XCTAssertTrue(storage.isAttributionComplete, "the gate is already closed")
        XCTAssertEqual(storage.cachedAttribution?.linkId, "link-deferred-1")
        XCTAssertNil(storage.checkBackoff)

        held.drain()
        guard case .success(let link?)? = results.all.first else {
            return XCTFail("expected the link, got \(String(describing: results.all.first))")
        }
        XCTAssertEqual(link.linkId, "link-deferred-1")
        XCTAssertEqual(results.all.count, 1)
    }

    // conformance: WL-S68

    func testANoMatchAnswerClosesTheGateEarlyToo() {
        configure(serving(CheckWire.noMatch))
        let held = HeldDelivery()
        held.install()

        WarpLink.checkDeferredDeepLink { _ in }

        XCTAssertTrue(storage.isAttributionComplete)
        held.drain()
    }

    func testAnAnswerThatIsNotFinalLeavesTheGateOpenUntilItIsHandled() {
        configure(serving(["matched": true]))
        let held = HeldDelivery()
        held.install()

        WarpLink.checkDeferredDeepLink { _ in }
        held.drain()

        XCTAssertFalse(storage.isAttributionComplete, "a match with nothing to route to is not final")
    }

    func testAFailureNeverClosesTheGate() {
        configure(serving { _ in CheckWire.offline })
        let held = HeldDelivery()
        held.install()

        WarpLink.checkDeferredDeepLink { _ in }
        held.drain()

        XCTAssertFalse(storage.isAttributionComplete)
    }

    func testAnAnswerThatArrivesAfterAReconfigureWritesNothing() {
        let transport = AnswerOnDemandTransport()
        makeSDKSynchronous(transport)
        WarpLink.configure(apiKey: liveKey, options: TestSupport.noAuto)
        WarpLink.fingerprintCollector = FingerprintCollector(vendorIdentifier: { [deviceId] in deviceId })
        WarpLink.checkDeferredDeepLink { _ in }
        // A different key abandons the running check, as a reconfigure does.
        WarpLink.configure(apiKey: testKey, options: TestSupport.noAuto)

        transport.answerMatches(CheckWire.matched)

        XCTAssertFalse(installMarkers.isMarked(StorageKeys(environment: .production).installCompleteMarker))
        XCTAssertFalse(storage.isAttributionComplete)
        XCTAssertNil(storage.cachedAttribution)
    }
}

/// Holds every match request open until the test answers it.
private final class AnswerOnDemandTransport: HTTPTransport {

    private var waiting: [(URLRequest, (Data?, URLResponse?, Error?) -> Void)] = []

    func send(
        _ request: URLRequest, completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> HTTPTask {
        guard request.url?.path.contains("/attribution/match") == true else {
            let (data, response, error) = CheckWire.answer(CheckWire.validated, for: request)
            completion(data, response, error)
            return CompletedHTTPTask()
        }
        waiting.append((request, completion))
        return CompletedHTTPTask()
    }

    func answerMatches(_ body: [String: Any]) {
        let pending = waiting
        waiting = []
        for (request, completion) in pending {
            let (data, response, error) = CheckWire.answer(body, for: request)
            completion(data, response, error)
        }
    }
}

/// `AttemptWatchdog.bound` gives the answer a way to take the attempt for good,
/// so an answer that is applied early cannot also be reported as a timeout.
final class AttemptClaimTests: XCTestCase {

    private final class Timer: ScheduledWork {
        func cancel() {}
    }

    override func tearDown() {
        SDKEnvironment.reset()
        super.tearDown()
    }

    func testAnAnswerBeforeTheTimerTakesTheAttemptAndTheTimerDoesNothing() {
        var fire: (() -> Void)?
        SDKEnvironment.armWatchdog = { _, work in fire = work; return Timer() }
        var claim: (() -> Bool)?
        let task = PendingTransport.Pending()

        _ = AttemptWatchdog.boundClaiming(timeout: 1, completion: { (_: Result<Int, WarpLinkError>) in }) { _, claimAnswer in
            claim = claimAnswer
            return task
        }

        XCTAssertEqual(claim?(), true)
        fire?()
        XCTAssertFalse(task.cancelled, "a claimed attempt is not cancelled by its timer")
    }

    func testAnAnswerAfterTheTimerFiredCannotTakeTheAttempt() {
        var fire: (() -> Void)?
        SDKEnvironment.armWatchdog = { _, work in fire = work; return Timer() }
        var claim: (() -> Bool)?
        let task = PendingTransport.Pending()

        _ = AttemptWatchdog.boundClaiming(timeout: 1, completion: { (_: Result<Int, WarpLinkError>) in }) { _, claimAnswer in
            claim = claimAnswer
            return task
        }
        fire?()

        XCTAssertTrue(task.cancelled)
        XCTAssertEqual(claim?(), false)
    }
}
