import Foundation
@testable import WarpLink

/// A transport that answers on the calling thread, from a script the test owns.
///
/// Nothing is queued and nothing is scheduled, so an SDK call started on the
/// test's thread has finished by the time it returns. Paired with synchronous
/// delivery (see `makeSDKSynchronous`), that lets a test assert on the next line
/// instead of sleeping and hoping the work landed.
///
/// It also records what was sent, which replaces the hand-rolled counters the
/// `URLProtocol` mocks needed to answer "how many requests did that make?".
final class InlineTransport: HTTPTransport {

    /// Answers one request with the same triple `URLSession` would hand back.
    typealias Respond = (URLRequest) -> (Data?, URLResponse?, Error?)

    private let respond: Respond
    let log = SentRequestLog()

    init(respond: @escaping Respond) {
        self.respond = respond
    }

    /// Every request the SDK made, in order.
    var requests: [URLRequest] { log.all }

    func requestCount(forPathContaining fragment: String) -> Int {
        log.count(forPathContaining: fragment)
    }

    /// The decoded body of the last request to a path containing `fragment`.
    func lastBody(forPathContaining fragment: String) -> [String: Any]? {
        bodies(forPathContaining: fragment).last
    }

    /// The decoded bodies of every request to a path containing `fragment`, in order.
    func bodies(forPathContaining fragment: String) -> [[String: Any]] {
        requests
            .filter { $0.url?.path.contains(fragment) == true }
            .compactMap { $0.resolvedHTTPBody }
            .compactMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
    }

    /// Answers on the calling thread, so it is finished before it returns and
    /// there is nothing left to stop.
    @discardableResult
    func send(
        _ request: URLRequest,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> HTTPTask {
        log.record(request)
        let (data, response, error) = respond(request)
        completion(data, response, error)
        return CompletedHTTPTask()
    }
}

extension InlineTransport {

    /// Serves a 200 whose JSON body is chosen by the request's path.
    static func serving(
        _ bodyForPath: @escaping (String) -> [String: Any]
    ) -> InlineTransport {
        InlineTransport { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let body = try? JSONSerialization.data(
                withJSONObject: bodyForPath(request.url?.path ?? "")
            )
            return (body, response, nil)
        }
    }

    /// Fails every request with `error`, for the offline paths.
    static func failing(with error: Error) -> InlineTransport {
        InlineTransport { _ in (nil, nil, error) }
    }
}

/// Close every one of the SDK's asynchronous boundaries for the rest of this test.
///
/// HTTP answers inline from `transport`, results are handed back on the calling
/// thread instead of hopping to the main queue, and a scheduled wait runs at
/// once, so every SDK entry point runs to completion before it returns.
///
/// Install it BEFORE `configure()`. The API client is built there and takes its
/// transport from the environment as it stands at that moment.
///
/// Undone by `WarpLink.reset()`, which every suite already calls in `tearDown`,
/// so an injection cannot leak into the next test.
func makeSDKSynchronous(_ transport: HTTPTransport) {
    SDKEnvironment.makeTransport = { transport }
    SDKEnvironment.deliver = { work in work() }
    // The third boundary. Nothing scheduled anything when these suites were
    // written, so closing it changes none of them; it stops a retry added later
    // from sleeping inside one.
    SDKEnvironment.schedule = { _, work in work() }
}

/// Every delay the SDK asked to wait, in order, with nothing actually waited.
///
/// A retry test asserts on this rather than on wall time: the budget it checks
/// is the budget it would otherwise have to spend.
final class ScheduleRecorder {

    private let lock = NSLock()
    private var recorded: [TimeInterval] = []

    var delays: [TimeInterval] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    /// Install after `makeSDKSynchronous`, which also closes this boundary.
    /// Undone by `WarpLink.reset()`.
    func install() {
        SDKEnvironment.schedule = { [weak self] delay, work in
            self?.lock.lock()
            self?.recorded.append(delay)
            self?.lock.unlock()
            work()
        }
    }
}
