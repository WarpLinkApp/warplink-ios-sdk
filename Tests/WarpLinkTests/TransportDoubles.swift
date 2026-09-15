import Foundation
@testable import WarpLink

// MARK: - Transports for the requests that are still open
//
// Moved out of `SynchronousSDK.swift`, which is about closing every asynchronous
// boundary so a test can assert on the next line. These two do the opposite:
// they hold a request open on purpose, because a supersede can only be observed
// while something is still on the wire.

/// A transport that accepts a resolve and never answers it, handing back a
/// handle that records whether anyone stopped it.
///
/// `InlineTransport` cannot take this shape: it answers on the calling thread
/// and returns `CompletedHTTPTask()`, so a request is over before the next tap
/// can arrive and cancelling it is a no-op. This one is the only way to prove
/// that superseding STOPS the older attempt rather than merely ignoring it.
final class PendingTransport: HTTPTransport {

    /// A request still on the wire, and whether it was cancelled.
    final class Pending: HTTPTask {
        private let lock = NSLock()
        private var stopped = false

        var cancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return stopped
        }

        func cancel() {
            lock.lock(); stopped = true; lock.unlock()
        }
    }

    private(set) var pending: [Pending] = []

    @discardableResult
    func send(
        _ request: URLRequest,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> HTTPTask {
        guard request.url?.path.contains("/links/resolve/") == true else {
            let ok = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            completion(
                try? JSONSerialization.data(
                    withJSONObject: ["valid": true, "domains": ["aplnk.to"]]
                ),
                ok, nil
            )
            return CompletedHTTPTask()
        }
        let task = Pending()
        pending.append(task)
        return task
    }
}

/// A transport that holds one path open and, when its handle is cancelled,
/// fails that request with `URLError(.cancelled)` exactly as `URLSession` does.
///
/// Deliberately not `PendingTransport`. That one proves a cancel REACHES the
/// request, and its tests assert that nothing has answered yet. This one proves
/// what the SDK does with the cancellation once it lands, which is the other
/// half and a different claim.
final class CancellingTransport: HTTPTransport {

    /// A request still on the wire, which answers its caller when cancelled.
    final class Held: HTTPTask {
        private let lock = NSLock()
        private var stopped = false
        private let completion: (Data?, URLResponse?, Error?) -> Void

        init(completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
            self.completion = completion
        }

        var cancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return stopped
        }

        func cancel() {
            lock.lock()
            let already = stopped
            stopped = true
            lock.unlock()
            // Cancelling twice must not answer twice, same as URLSession.
            guard !already else { return }
            completion(nil, nil, URLError(.cancelled))
        }
    }

    /// Answers one request with the same triple `URLSession` would hand back.
    typealias Respond = (URLRequest) -> (Data?, URLResponse?, Error?)

    private let heldPath: String
    private let heldLimit: Int
    private let respondAfterLimit: Respond
    private(set) var held: [Held] = []
    /// Every request, so a re-tap test can count them and read their tap ids.
    let log = SentRequestLog()

    /// Holds every request whose path contains `heldPath`.
    convenience init(holdingPathContaining heldPath: String) {
        self.init(
            holding: .max,
            requestsForPathContaining: heldPath,
            thenAnswering: { _ in (nil, nil, URLError(.unknown)) }
        )
    }

    /// Holds the first `heldLimit` matching requests and answers the rest from
    /// `respond`.
    ///
    /// The shape a re-tap needs: the first tap has to be STILL OPEN when the
    /// second arrives, and the second has to succeed, so a transport that holds
    /// everything cannot express it.
    init(
        holding heldLimit: Int,
        requestsForPathContaining heldPath: String,
        thenAnswering respond: @escaping Respond
    ) {
        self.heldPath = heldPath
        self.heldLimit = heldLimit
        self.respondAfterLimit = respond
    }

    @discardableResult
    func send(
        _ request: URLRequest,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> HTTPTask {
        log.record(request)
        guard request.url?.path.contains(heldPath) == true else {
            let ok = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            completion(
                try? JSONSerialization.data(
                    withJSONObject: ["valid": true, "domains": ["aplnk.to"]]
                ),
                ok, nil
            )
            return CompletedHTTPTask()
        }
        guard held.count < heldLimit else {
            let (data, response, error) = respondAfterLimit(request)
            completion(data, response, error)
            return CompletedHTTPTask()
        }
        let task = Held(completion: completion)
        held.append(task)
        return task
    }
}
