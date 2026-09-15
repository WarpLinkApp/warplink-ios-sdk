import XCTest
@testable import WarpLink

/// Which failures are worth a second attempt, and which are refusals the server
/// will simply repeat.
final class RetryPolicyTests: XCTestCase {

    private func urlError(_ code: URLError.Code) -> WarpLinkError {
        .networkError(URLError(code))
    }

    func testTransientTransportFailuresAreRetried() {
        for code: URLError.Code in [
            .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
            .networkConnectionLost, .notConnectedToInternet, .dataNotAllowed,
        ] {
            XCTAssertTrue(RetryPolicy.isRetryable(urlError(code)), "\(code)")
        }
    }

    func testACancelledRequestIsRetried() {
        // `.cancelled` is what a supersede or a reconfigure causes on purpose,
        // but it is ALSO what the OS reports for a connection that died while
        // the app was suspended: a live tap reusing that connection fails this
        // way too (warplink-i7oa). `isRetryable` cannot tell the two apart, and
        // it does not need to: `BoundedRetry` already asks `isCurrent()` before
        // it ever asks this, so a superseded or abandoned attempt never reaches
        // here with a chance to retry. Whatever does reach here is still
        // wanted, so it is worth another attempt like any other transient
        // failure.
        XCTAssertTrue(RetryPolicy.isRetryable(urlError(.cancelled)))
    }

    func testANonURLErrorIsNotRetried() {
        // .networkError carries a bare Error and nothing else casts it. Anything
        // that is not a URLError is not a diagnosis we can act on.
        struct Odd: Error {}
        XCTAssertFalse(RetryPolicy.isRetryable(.networkError(Odd())))
    }

    func testOnly5xxIsRetriedAmongServerErrors() {
        XCTAssertTrue(RetryPolicy.isRetryable(.serverError(statusCode: 500, message: "")))
        XCTAssertTrue(RetryPolicy.isRetryable(.serverError(statusCode: 503, message: "")))
        // The parser's `default:` branch produces .serverError for these two as
        // well. An expired link and a rate limit are refusals, not weather.
        XCTAssertFalse(RetryPolicy.isRetryable(.serverError(statusCode: 410, message: "")))
        XCTAssertFalse(RetryPolicy.isRetryable(.serverError(statusCode: 429, message: "")))
        // statusCode 0 stands for "Invalid URL" and for "No HTTP response".
        // The first is permanent and the second says nothing a retry can fix.
        XCTAssertFalse(RetryPolicy.isRetryable(.serverError(statusCode: 0, message: "Invalid URL")))
    }

    func testEveryRefusalIsFinal() {
        for error: WarpLinkError in [
            .notConfigured, .invalidApiKeyFormat, .invalidApiKey,
            .invalidURL, .linkNotFound, .passwordRequired,
        ] {
            XCTAssertFalse(RetryPolicy.isRetryable(error), "\(error)")
        }
        XCTAssertFalse(RetryPolicy.isRetryable(.decodingError(URLError(.badURL))))
    }

    func testThreeAttemptsAndNoMore() {
        XCTAssertEqual(RetryPolicy.maxAttempts, 3)
        XCTAssertNil(RetryPolicy.delay(beforeAttempt: 1), "attempt 1 never waits")
        XCTAssertNotNil(RetryPolicy.delay(beforeAttempt: 2))
        XCTAssertNotNil(RetryPolicy.delay(beforeAttempt: 3))
        XCTAssertNil(RetryPolicy.delay(beforeAttempt: 4), "the budget is spent")
    }

    // conformance: WL-S27
    func testMaxAttemptsIsTheBoundAndNotTheLengthOfTheWaitSchedule() {
        // A constant named "max attempts" that bounds nothing is a trap for the
        // next reader: raising it would change no behaviour, and the real bound
        // would sit unnamed in the length of `baseDelays`. Every attempt up to
        // `maxAttempts` gets a wait, and the one after it gets none, whatever
        // the schedule's length.
        for attempt in 2...RetryPolicy.maxAttempts {
            XCTAssertNotNil(RetryPolicy.delay(beforeAttempt: attempt), "attempt \(attempt)")
        }
        XCTAssertNil(RetryPolicy.delay(beforeAttempt: RetryPolicy.maxAttempts + 1))
    }

    func testTheWaitsStayInsideTheBudget() {
        let second = try! XCTUnwrap(RetryPolicy.delay(beforeAttempt: 2))
        let third = try! XCTUnwrap(RetryPolicy.delay(beforeAttempt: 3))
        XCTAssertGreaterThanOrEqual(second, 0.5)
        XCTAssertGreaterThanOrEqual(third, 1.0)
        // Roughly half a second then a second, plus jitter. A deep link
        // delivered thirty seconds after the tap is its own defect.
        XCTAssertLessThan(second + third, 2.0)
    }

    func testEveryAttemptIsBoundedIncludingTheFirst() {
        // The SDK sets no timeout of its own anywhere in Sources/, so an
        // unbounded first attempt inherits URLSession's 60 second default. On a
        // network that hangs rather than fails it would spend the whole budget
        // and no retry would ever run.
        XCTAssertEqual(RetryPolicy.timeout(forAttempt: 1), 4.0)
        XCTAssertEqual(RetryPolicy.timeout(forAttempt: 2), 3.0)
        XCTAssertEqual(RetryPolicy.timeout(forAttempt: 3), 3.0)
    }

    func testTheWorstCaseFitsTheBudget() {
        let attempts = (1...RetryPolicy.maxAttempts)
            .map { RetryPolicy.timeout(forAttempt: $0) }
            .reduce(0, +)
        let waits = RetryPolicy.baseDelays.reduce(0, +)
            + Double(RetryPolicy.baseDelays.count) * RetryPolicy.maxJitter
        // 4 + 0.5 + 3 + 1 + 3, plus at most two jitters. About twelve seconds,
        // not four: four was the number the rejected draft could afford only
        // because it never bounded the first attempt.
        XCTAssertEqual(RetryPolicy.totalBudget, 12.0)
        XCTAssertLessThanOrEqual(attempts + waits, RetryPolicy.totalBudget)
    }
}
