import XCTest
@testable import WarpLink

/// The retry driver itself, with no SDK around it.
final class BoundedRetryTests: XCTestCase {

    private var recorder: ScheduleRecorder!

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        recorder = ScheduleRecorder()
        recorder.install()
    }

    override func tearDown() {
        WarpLink.reset()
        recorder = nil
        super.tearDown()
    }

    private func transient() -> WarpLinkError { .networkError(URLError(.timedOut)) }

    func testASuccessOnTheFirstAttemptRunsOnce() {
        var attempts = 0
        var delivered: Result<Int, WarpLinkError>?

        BoundedRetry.run(isCurrent: { true }, attempt: { _, done in
            attempts += 1
            done(.success(7))
        }, completion: { delivered = $0 })

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(recorder.delays.count, 0)
        guard case .success(7)? = delivered else { return XCTFail("expected 7") }
    }

    func testATransientFailureThenASuccessDeliversOnce() {
        var attempts = 0
        var deliveries = 0

        BoundedRetry.run(isCurrent: { true }, attempt: { number, done in
            attempts += 1
            done(number == 1 ? .failure(self.transient()) : .success(number))
        }, completion: { _ in deliveries += 1 })

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(deliveries, 1)
        XCTAssertEqual(recorder.delays.count, 1)
    }

    func testThreeTransientFailuresStopAtThree() {
        var attempts = 0
        var delivered: Result<Int, WarpLinkError>?

        BoundedRetry.run(isCurrent: { true }, attempt: { _, done in
            attempts += 1
            done(.failure(self.transient()))
        }, completion: { delivered = $0 })

        // Exactly three. An unbounded loop is the mutation this pins.
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(recorder.delays.count, 2)
        guard case .failure(.networkError)? = delivered else {
            return XCTFail("expected the last failure to reach the caller")
        }
    }

    func testARefusalIsNotRetried() {
        var attempts = 0
        BoundedRetry.run(isCurrent: { true }, attempt: { _, done in
            attempts += 1
            done(.failure(.linkNotFound) as Result<Int, WarpLinkError>)
        }, completion: { _ in })
        XCTAssertEqual(attempts, 1)
    }

    func testASupersededRunStopsRetryingAndStillAnswersItsOwnCaller() {
        var attempts = 0
        var deliveries = 0

        BoundedRetry.run(isCurrent: { false }, attempt: { _, done in
            attempts += 1
            done(.failure(self.transient()) as Result<Int, WarpLinkError>)
        }, completion: { _ in deliveries += 1 })

        // Stops the network work, but still answers. Silencing the host is the
        // caller's job: swallowing the completion here would strand a manual
        // `handleDeepLink` caller and, on Android, anyone parked on the claim.
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(deliveries, 1)
        // And it stops at once rather than waiting out a backoff it will not use.
        XCTAssertEqual(recorder.delays.count, 0)
    }

    func testASupersedeDuringTheWaitStopsTheNextAttempt() {
        // The shape a real supersede takes: the newer tap arrives while the
        // older one is waiting out its backoff, not before it ever started.
        var current = true
        SDKEnvironment.schedule = { _, work in
            current = false
            work()
        }

        var attempts = 0
        var deliveries = 0

        BoundedRetry.run(isCurrent: { current }, attempt: { _, done in
            attempts += 1
            done(.failure(self.transient()) as Result<Int, WarpLinkError>)
        }, completion: { _ in deliveries += 1 })

        XCTAssertEqual(attempts, 1, "the wait ended on work that is no longer wanted")
        XCTAssertEqual(deliveries, 1)
    }

    func testAnElapsedRunStopsEarlyEvenWithAttemptsLeft() {
        // The clock the SDK already injects for the dedupe window. Jump it past
        // the budget after the first attempt.
        var now: TimeInterval = 0
        WarpLink.monotonicNow = { now }

        var attempts = 0
        BoundedRetry.run(isCurrent: { true }, attempt: { _, done in
            attempts += 1
            now += RetryPolicy.totalBudget + 1
            done(.failure(self.transient()) as Result<Int, WarpLinkError>)
        }, completion: { _ in })

        // One slow attempt spends the whole budget. Two more would push a tap's
        // answer well past the point where the user has moved on.
        XCTAssertEqual(attempts, 1)
    }
}
