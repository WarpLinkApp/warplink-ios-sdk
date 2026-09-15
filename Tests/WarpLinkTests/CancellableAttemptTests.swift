import XCTest
@testable import WarpLink

/// Accepts the connection and never answers, which is the network this whole
/// change exists for: attempt 1 hangs rather than failing.
private final class HangingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}

/// An attempt that is on the wire can be stopped, not merely ignored.
///
/// `send` returned Void and `URLSessionTransport` threw the data task away on
/// the line it resumed it, so a superseded tap kept its connection open for the
/// whole timeout on the network least able to spare it. These two tests are what
/// stop the handle from regressing to a nominal one: a conformer that returned
/// `CompletedHTTPTask()` would still satisfy the type.
final class CancellableAttemptTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HangingURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        WarpLink.reset()
        session = nil
        super.tearDown()
    }

    func testCancellingTheTransportHandleStopsTheRequest() {
        let exp = expectation(description: "completion")
        var seen: Error?

        let task = URLSessionTransport(session: session).send(hangingRequest) { _, _, error in
            seen = error
            exp.fulfill()
        }
        task.cancel()

        wait(for: [exp], timeout: 5)
        XCTAssertEqual((seen as? URLError)?.code, .cancelled)
    }

    func testCancellingResolvesHandleStopsThatAttempt() {
        let client = APIClient(
            apiKey: "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
            baseURL: "https://api.warplink.app/v1",
            transport: URLSessionTransport(session: session)
        )

        let exp = expectation(description: "completion")
        var seen: Error?

        let task = client.resolveLink(
            slug: "abc123", domain: "aplnk.to", timeout: 30
        ) { result in
            if case let .failure(.networkError(underlying)) = result { seen = underlying }
            exp.fulfill()
        }
        task.cancel()

        // Well inside the 30 s this attempt asked for: the answer arrives
        // because the request stopped, not because it timed out.
        wait(for: [exp], timeout: 5)
        XCTAssertEqual((seen as? URLError)?.code, .cancelled)
    }

    private var hangingRequest: URLRequest {
        URLRequest(url: URL(string: "https://api.warplink.app/v1/links/resolve/abc123")!)
    }
}
