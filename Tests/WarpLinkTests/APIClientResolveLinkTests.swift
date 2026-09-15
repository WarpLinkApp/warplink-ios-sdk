import XCTest
@testable import WarpLink

// MARK: - URLProtocol Mock

private class MockURLProtocol: URLProtocol {

    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Tests

final class APIClientResolveLinkTests: XCTestCase {

    private let testApiKey = "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    private let baseURL = "https://api.warplink.app/v1"
    private var client: APIClient!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        client = APIClient(apiKey: testApiKey, baseURL: baseURL, transport: URLSessionTransport(session: session))
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testResolveLinkSuccess200() {
        let json: [String: Any] = [
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "slug": "abc123",
            "domain": "aplnk.to",
            "destination_url": "https://example.com",
            "ios_url": "myapp://page",
            "ios_fallback_url": NSNull(),
            "custom_params": ["promo": "summer"],
            "created_at": "2026-01-01T00:00:00.000Z",
        ]
        mockResponse(statusCode: 200, json: json)

        let exp = expectation(description: "completion")
        client.resolveLink(slug: "abc123", domain: "aplnk.to") { result in
            guard case .success(let response) = result else {
                XCTFail("Expected success, got \(result)")
                exp.fulfill()
                return
            }
            XCTAssertEqual(response.id, "550e8400-e29b-41d4-a716-446655440000")
            XCTAssertEqual(response.slug, "abc123")
            XCTAssertEqual(response.domain, "aplnk.to")
            XCTAssertEqual(response.destinationUrl, "https://example.com")
            XCTAssertEqual(response.iosUrl, "myapp://page")
            XCTAssertNil(response.iosFallbackUrl)
            XCTAssertEqual(response.customParams["promo"]?.stringValue, "summer")
            XCTAssertEqual(response.createdAt, "2026-01-01T00:00:00.000Z")
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testResolveLink404ReturnsLinkNotFound() {
        mockResponse(statusCode: 404, json: ["error": "Not found"])

        let exp = expectation(description: "completion")
        client.resolveLink(slug: "missing", domain: "aplnk.to") { result in
            if case .failure(let error) = result {
                if case .linkNotFound = error {
                    // Expected
                } else {
                    XCTFail("Expected linkNotFound, got \(error)")
                }
            } else {
                XCTFail("Expected failure, got \(result)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testResolveLink401ReturnsInvalidApiKey() {
        mockResponse(statusCode: 401, json: ["error": "Unauthorized"])

        let exp = expectation(description: "completion")
        client.resolveLink(slug: "abc123", domain: "aplnk.to") { result in
            if case .failure(let error) = result {
                if case .invalidApiKey = error {
                    // Expected
                } else {
                    XCTFail("Expected invalidApiKey, got \(error)")
                }
            } else {
                XCTFail("Expected failure, got \(result)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testResolveLink403PasswordRequiredReturnsPasswordRequired() {
        mockResponse(statusCode: 403, json: [
            "error": [
                "code": "PASSWORD_REQUIRED",
                "message": "This link is password protected.",
            ],
        ])

        let exp = expectation(description: "completion")
        client.resolveLink(slug: "secret", domain: "aplnk.to") { result in
            if case .failure(let error) = result {
                if case .passwordRequired = error {
                    // Expected
                } else {
                    XCTFail("Expected passwordRequired, got \(error)")
                }
            } else {
                XCTFail("Expected failure, got \(result)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testResolveLink403WithoutPasswordCodeStillReturnsInvalidApiKey() {
        // A 403 is also how a rejected key answers. Only the body's code tells
        // the two apart, so a refusal that carries no code must keep the old
        // meaning rather than accusing every 403 of being password protected.
        mockResponse(statusCode: 403, json: ["error": ["code": "FORBIDDEN"]])

        let exp = expectation(description: "completion")
        client.resolveLink(slug: "abc123", domain: "aplnk.to") { result in
            if case .failure(let error) = result {
                if case .invalidApiKey = error {
                    // Expected
                } else {
                    XCTFail("Expected invalidApiKey, got \(error)")
                }
            } else {
                XCTFail("Expected failure, got \(result)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testResolveLinkRequestHeaders() {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "User-Agent"),
                "WarpLink-iOS/\(WarpLink.sdkVersion)"
            )
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/links/resolve/abc123")
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let domainParam = components.queryItems?.first { $0.name == "domain" }
            XCTAssertEqual(domainParam?.value, "aplnk.to")

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let json = validResponseJSON()
            let data = try JSONSerialization.data(withJSONObject: json)
            return (response, data)
        }

        let exp = expectation(description: "completion")
        client.resolveLink(slug: "abc123", domain: "aplnk.to") { _ in exp.fulfill() }
        waitForExpectations(timeout: 2)
    }

    func testResolveLinkNetworkError() {
        MockURLProtocol.requestHandler = { _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        }

        let exp = expectation(description: "completion")
        client.resolveLink(slug: "abc123", domain: "aplnk.to") { result in
            if case .failure(let error) = result {
                if case .networkError = error {
                    // Expected
                } else {
                    XCTFail("Expected networkError, got \(error)")
                }
            } else {
                XCTFail("Expected failure, got \(result)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    // conformance: WL-S17
    func testResolveLinkNullIosUrl() {
        let json: [String: Any] = [
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "slug": "abc123",
            "domain": "aplnk.to",
            "destination_url": "https://example.com",
            "ios_url": NSNull(),
            "ios_fallback_url": NSNull(),
            "custom_params": ["promo": "summer"],
            "created_at": "2026-01-01T00:00:00.000Z",
        ]
        mockResponse(statusCode: 200, json: json)

        let exp = expectation(description: "completion")
        client.resolveLink(slug: "abc123", domain: "aplnk.to") { result in
            guard case .success(let response) = result else {
                XCTFail("Expected success, got \(result)")
                exp.fulfill()
                return
            }
            XCTAssertNil(response.iosUrl)
            XCTAssertNil(response.iosFallbackUrl)
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testResolveLinkEmptyCustomParams() {
        var json = validResponseJSON()
        json["custom_params"] = [String: Any]()
        mockResponse(statusCode: 200, json: json)

        let exp = expectation(description: "completion")
        client.resolveLink(slug: "abc123", domain: "aplnk.to") { result in
            guard case .success(let response) = result else {
                XCTFail("Expected success, got \(result)")
                exp.fulfill()
                return
            }
            XCTAssertTrue(response.customParams.isEmpty)
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    // MARK: - One tap id per tap, and a bound on every attempt

    // A 404 is used deliberately in the three below: it is not retryable, so
    // they stay at one real round trip each even after the bounded retry lands.

    func testTheTapIdTravelsAsAHeader() {
        var seen: String?
        MockURLProtocol.requestHandler = { request in
            seen = request.value(forHTTPHeaderField: "X-WarpLink-Tap-Id")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let exp = expectation(description: "completion")
        client.resolveLink(
            slug: "abc123", domain: "aplnk.to",
            tapId: "0b6e7a3c-6c5a-4a2e-9f0e-2d9a1c7b4e11"
        ) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2)

        XCTAssertEqual(seen, "0b6e7a3c-6c5a-4a2e-9f0e-2d9a1c7b4e11")
    }

    func testNoTapIdMeansNoHeader() {
        var present = true
        MockURLProtocol.requestHandler = { request in
            present = request.value(forHTTPHeaderField: "X-WarpLink-Tap-Id") != nil
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let exp = expectation(description: "completion")
        client.resolveLink(slug: "abc123", domain: "aplnk.to") { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2)

        XCTAssertFalse(present)
    }

    func testTheAttemptTimeoutReachesTheRequest() {
        // That the SDK sets one at all. That URLSession honours it is proved end
        // to end by the accepted-and-never-answered test in Task 9.
        var seen: TimeInterval?
        MockURLProtocol.requestHandler = { request in
            seen = request.timeoutInterval
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let exp = expectation(description: "completion")
        client.resolveLink(
            slug: "abc123", domain: "aplnk.to", timeout: 4
        ) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2)

        XCTAssertEqual(seen, 4)
    }

    // MARK: - Helpers

    private func mockResponse(statusCode: Int, json: [String: Any]) {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode,
                httpVersion: nil, headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: json)
            return (response, data)
        }
    }
}

private func validResponseJSON() -> [String: Any] {
    [
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "slug": "abc123",
        "domain": "aplnk.to",
        "destination_url": "https://example.com",
        "ios_url": "myapp://page",
        "ios_fallback_url": NSNull(),
        "custom_params": ["promo": "summer"],
        "created_at": "2026-01-01T00:00:00.000Z",
    ]
}
