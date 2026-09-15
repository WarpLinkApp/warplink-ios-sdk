import Foundation

/// A request that is on the wire and can be stopped.
///
/// `send` returned Void and `URLSessionTransport` threw the data task away on the
/// line it resumed it, so a superseded tap could only be ignored, never stopped,
/// and its connection stayed open for the whole timeout. Handing the handle back
/// is what makes "a newer tap cancels the older one" real rather than nominal.
protocol HTTPTask {
    func cancel()
}

/// `URLSessionTask` already declares exactly this method.
extension URLSessionTask: HTTPTask {}

/// The handle for work that is already over by the time the caller sees it: an
/// inline transport, or a request that failed before it was built.
struct CompletedHTTPTask: HTTPTask {
    func cancel() {}
}

/// One HTTP round trip: everything `APIClient` needs from the network.
///
/// The signature mirrors `URLSession.dataTask`'s completion deliberately, so the
/// response parsers above it are unchanged and this stays a seam rather than an
/// abstraction with opinions of its own.
protocol HTTPTransport {
    /// Discardable because two of the three call sites never cancel: key
    /// validation, and every test that only cares about the answer.
    @discardableResult
    func send(
        _ request: URLRequest,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> HTTPTask

    /// Stop reusing the connections this transport holds, so the next request
    /// goes out on a new one.
    ///
    /// Called when an attempt's watchdog fires, because a timeout is one
    /// failure that says the connection itself may be dead (bead: warplink-qr6k),
    /// and also when an attempt ends in `URLError(.cancelled)` that the
    /// watchdog did not cause, because a connection that died while the app was
    /// suspended reports that same code (bead: warplink-i7oa). Over HTTP/2
    /// every request to a host shares one pooled connection, and cancelling a
    /// task resets only its stream, so without this a retry rides the same
    /// dead connection as the attempt it replaces.
    func discardConnections()
}

extension HTTPTransport {
    /// A transport with no connections of its own, which is every test double,
    /// has nothing to discard.
    func discardConnections() {}
}

/// The transport every shipped build uses.
///
/// Takes a `URLSession` so a host with its own configuration (pinning, a
/// custom `URLProtocol`, a shared background session) can supply one, and so a
/// test can drive the real networking stack when that is what it means to test.
/// A test that instead wants no networking at all injects a different
/// `HTTPTransport` through `SDKEnvironment`.
///
/// A class, and locked, because `discardConnections` replaces the session from
/// the watchdog's queue while `send` may be reading it from another.
final class URLSessionTransport: HTTPTransport {

    private let lock = NSLock()
    private var session: URLSession
    /// Whether `session` was made here. Only a session this transport made is
    /// its own to end: a host's session, `.shared` included, is never
    /// invalidated, because the host is still using it.
    private var ownsSession = false

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// The session the next request goes out on.
    var currentSession: URLSession {
        lock.lock(); defer { lock.unlock() }
        return session
    }

    @discardableResult
    func send(
        _ request: URLRequest,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> HTTPTask {
        let task = currentSession.dataTask(with: request, completionHandler: completion)
        task.resume()
        return task
    }

    /// Moves every later request onto a new session, which has no pooled
    /// connection to reuse. Built from the old session's configuration,
    /// delegate and queue, so a host's pinning or custom protocol survives.
    ///
    /// Not `URLSession.flush(completionHandler:)`, which also promises a new
    /// connection: it answers asynchronously, and the retry must not be sent
    /// before it has. Replacing the session takes effect on the next line.
    func discardConnections() {
        lock.lock()
        let old = session
        let owned = ownsSession
        session = URLSession(
            configuration: old.configuration,
            delegate: old.delegate,
            delegateQueue: old.delegateQueue
        )
        ownsSession = true
        lock.unlock()
        // Lets the abandoned attempt's cancellation land first, then releases
        // every connection the old session was holding.
        if owned { old.finishTasksAndInvalidate() }
    }
}
