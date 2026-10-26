import Foundation
@testable import WarpLink

/// A transport that holds the requests `shouldHold` picks and lets the test
/// answer them later, in any order against the requests it answers inline.
///
/// Cancelling a held request only records it. The answer can still land
/// afterwards, which is the late answer a real cancel cannot always stop.
final class GatedTransport: HTTPTransport {

    final class Held: HTTPTask {
        private let lock = NSLock()
        private var stopped = false
        fileprivate let completion: (Data?, URLResponse?, Error?) -> Void

        fileprivate init(completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
            self.completion = completion
        }

        var cancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return stopped
        }

        func cancel() {
            lock.lock(); stopped = true; lock.unlock()
        }
    }

    private let shouldHold: (URLRequest) -> Bool
    private let respond: (URLRequest) -> (Data?, URLResponse?, Error?)
    private(set) var held: [Held] = []

    init(
        holding shouldHold: @escaping (URLRequest) -> Bool,
        otherwise respond: @escaping (URLRequest) -> (Data?, URLResponse?, Error?)
    ) {
        self.shouldHold = shouldHold
        self.respond = respond
    }

    @discardableResult
    func send(
        _ request: URLRequest,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> HTTPTask {
        guard shouldHold(request) else {
            let (data, response, error) = respond(request)
            completion(data, response, error)
            return CompletedHTTPTask()
        }
        let task = Held(completion: completion)
        held.append(task)
        return task
    }

    /// Answers the held request at `index` as the server would.
    func release(_ index: Int = 0, status: Int, body: [String: Any]) {
        let url = URL(string: "https://api.warplink.app/v1/attribution/match")!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        held[index].completion(try? JSONSerialization.data(withJSONObject: body), response, nil)
    }
}
