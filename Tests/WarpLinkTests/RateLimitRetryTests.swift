import XCTest
@testable import WarpLink

/// A 429 gets one retry after the server's `Retry-After`, capped at five
/// seconds, and otherwise reaches the caller as `.serverError(429)`.
final class RateLimitRetryTests: XCTestCase {

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

    private func limited(retryAfter: String?) -> WarpLinkError {
        let headers = retryAfter.map { ["Retry-After": $0] }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.warplink.app/v1/x")!,
            statusCode: 429, httpVersion: nil, headerFields: headers
        )!
        return RateLimit.error(for: response)
    }

    /// Runs `BoundedRetry` against an attempt that always answers `failure`,
    /// and returns how many attempts ran.
    private func attempts(until failure: WarpLinkError) -> Int {
        var count = 0
        BoundedRetry.run(isCurrent: { true }, attempt: { _, done in
            count += 1
            done(.failure(failure) as Result<Int, WarpLinkError>)
        }, completion: { _ in })
        return count
    }

    func testARetryAfterOfThreeSecondsRetriesOnceAfterThreeSeconds() {
        XCTAssertEqual(attempts(until: limited(retryAfter: "3")), 2)
        XCTAssertEqual(recorder.delays, [3.0])
    }

    func testARetryAfterOfExactlyFiveSecondsStillRetries() {
        XCTAssertEqual(attempts(until: limited(retryAfter: "5")), 2)
        XCTAssertEqual(recorder.delays, [5.0])
    }

    func testARetryAfterOverFiveSecondsIsNotRetried() {
        XCTAssertEqual(attempts(until: limited(retryAfter: "6")), 1)
        XCTAssertTrue(recorder.delays.isEmpty)
    }

    func testAMissingRetryAfterRetriesOnceAfterOneSecond() {
        XCTAssertEqual(attempts(until: limited(retryAfter: nil)), 2)
        XCTAssertEqual(recorder.delays, [1.0])
    }

    func testAnUnreadableRetryAfterFallsBackToOneSecond() {
        for header in ["soon", "-2", "Wed, 21 Oct 2026 07:28:00 GMT"] {
            recorder = ScheduleRecorder()
            recorder.install()
            XCTAssertEqual(attempts(until: limited(retryAfter: header)), 2, header)
            XCTAssertEqual(recorder.delays, [1.0], header)
        }
    }

    func testASecond429IsNotRetriedAgain() {
        XCTAssertEqual(attempts(until: limited(retryAfter: "1")), 2)
        XCTAssertEqual(recorder.delays.count, 1)
    }

    func testTheRetryOutcomeReachesTheCallerOnce() {
        var attempt = 0
        var deliveries = 0
        var delivered: Result<Int, WarpLinkError>?
        BoundedRetry.run(isCurrent: { true }, attempt: { _, done in
            attempt += 1
            done(attempt == 1 ? .failure(self.limited(retryAfter: "2")) : .success(9))
        }, completion: { delivered = $0; deliveries += 1 })
        XCTAssertEqual(deliveries, 1)
        guard case .success(9)? = delivered else { return XCTFail("expected the retry's 9") }
    }

    func testAnExhaustedRateLimitSurfacesAsAServerError429() {
        var delivered: Result<Int, WarpLinkError>?
        let error = limited(retryAfter: "9")
        BoundedRetry.run(isCurrent: { true }, attempt: { _, done in
            done(.failure(error))
        }, completion: { delivered = $0 })
        guard case let .failure(.serverError(code, _))? = delivered else {
            return XCTFail("expected serverError")
        }
        XCTAssertEqual(code, 429)
    }

    func testASupersededRunDoesNotRetryARateLimit() {
        var count = 0
        BoundedRetry.run(isCurrent: { false }, attempt: { _, done in
            count += 1
            done(.failure(self.limited(retryAfter: "1")) as Result<Int, WarpLinkError>)
        }, completion: { _ in })
        XCTAssertEqual(count, 1)
    }

    func testOtherClientErrorsAreStillFinal() {
        XCTAssertEqual(attempts(until: .serverError(statusCode: 410, message: "")), 1)
        XCTAssertFalse(RateLimit.isRateLimited(.serverError(statusCode: 503, message: "")))
        XCTAssertNil(RateLimit.wait(for: .serverError(statusCode: 503, message: "")))
    }

    func testARetryAfterJustOverFiveSecondsIsNotRetried() {
        XCTAssertEqual(attempts(until: limited(retryAfter: "5.0001")), 1)
        XCTAssertNil(RateLimit.wait(for: limited(retryAfter: "5.0001")))
    }

    func testA500Then429Then200DeliversThe200() {
        var attempt = 0
        var delivered: Result<Int, WarpLinkError>?
        BoundedRetry.run(isCurrent: { true }, attempt: { _, done in
            attempt += 1
            switch attempt {
            case 1: done(.failure(.serverError(statusCode: 500, message: "")))
            case 2: done(.failure(self.limited(retryAfter: "2")))
            default: done(.success(200))
            }
        }, completion: { delivered = $0 })
        XCTAssertEqual(attempt, 3)
        XCTAssertEqual(recorder.delays.last, 2.0)
        guard case .success(200)? = delivered else { return XCTFail("expected 200") }
    }

    func testA429RetryThatWouldPassTheMaxAttemptsIsNotSent() {
        var attempt = 0
        BoundedRetry.run(isCurrent: { true }, attempt: { _, done in
            attempt += 1
            done(.failure(attempt < 3 ? .serverError(statusCode: 500, message: "") : self.limited(retryAfter: "1"))
                as Result<Int, WarpLinkError>)
        }, completion: { _ in })
        XCTAssertEqual(attempt, 3)
    }
}
