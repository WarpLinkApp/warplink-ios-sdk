import XCTest
@testable import WarpLink

// MARK: - URLProtocol Mock (Global)

private class HandleDeepLinkMockProtocol: URLProtocol {

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

final class HandleDeepLinkTests: XCTestCase {

    private let testApiKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        URLProtocol.registerClass(HandleDeepLinkMockProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(HandleDeepLinkMockProtocol.self)
        HandleDeepLinkMockProtocol.requestHandler = nil
        WarpLink.reset()
        super.tearDown()
    }

    func testHandleDeepLinkNotConfigured() {
        let exp = expectation(description: "completion")
        WarpLink.handleDeepLink(URL(string: "https://aplnk.to/abc123")!) { result in
            if case .failure(let error) = result, case .notConfigured = error {
                // Expected
            } else {
                XCTFail("Expected notConfigured, got \(result)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testHandleDeepLinkInvalidURL() {
        configureSDK()

        let exp = expectation(description: "completion")
        WarpLink.handleDeepLink(URL(string: "https://example.com/page")!) { result in
            if case .failure(let error) = result, case .invalidURL = error {
                // Expected
            } else {
                XCTFail("Expected invalidURL, got \(result)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testHandleDeepLinkSuccess() {
        configureSDK()
        mockResolveResponse(statusCode: 200, json: validLinkJSON())

        let exp = expectation(description: "completion")
        WarpLink.handleDeepLink(URL(string: "https://aplnk.to/abc123")!) { result in
            guard case .success(let deepLink) = result else {
                XCTFail("Expected success, got \(result)")
                exp.fulfill()
                return
            }
            XCTAssertEqual(deepLink.linkId, "550e8400-e29b-41d4-a716-446655440000")
            XCTAssertEqual(deepLink.destination, "https://example.com")
            XCTAssertEqual(deepLink.deepLinkUrl, "myapp://page")
            XCTAssertEqual(deepLink.customParams["promo"] as? String, "summer")
            XCTAssertFalse(deepLink.isDeferred)
            XCTAssertEqual(deepLink.matchType, .deterministic)
            XCTAssertEqual(deepLink.matchConfidence, 1.0)
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testHandleDeepLink404() {
        configureSDK()
        mockResolveResponse(statusCode: 404, json: ["error": "Not found"])

        let exp = expectation(description: "completion")
        WarpLink.handleDeepLink(URL(string: "https://aplnk.to/missing")!) { result in
            if case .failure(let error) = result, case .linkNotFound = error {
                // Expected
            } else {
                XCTFail("Expected linkNotFound, got \(result)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testHandleDeepLinkWithQueryParams() {
        configureSDK()
        mockResolveResponse(statusCode: 200, json: validLinkJSON())

        let exp = expectation(description: "completion")
        let url = URL(string: "https://aplnk.to/abc123?utm_source=twitter")!
        WarpLink.handleDeepLink(url) { result in
            guard case .success(let deepLink) = result else {
                XCTFail("Expected success, got \(result)")
                exp.fulfill()
                return
            }
            XCTAssertEqual(deepLink.linkId, "550e8400-e29b-41d4-a716-446655440000")
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testHandleDeepLinkWithTrailingSlash() {
        configureSDK()
        mockResolveResponse(statusCode: 200, json: validLinkJSON())

        let exp = expectation(description: "completion")
        let url = URL(string: "https://aplnk.to/abc123/")!
        WarpLink.handleDeepLink(url) { result in
            guard case .success(let deepLink) = result else {
                XCTFail("Expected success, got \(result)")
                exp.fulfill()
                return
            }
            XCTAssertEqual(deepLink.linkId, "550e8400-e29b-41d4-a716-446655440000")
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testHandleDeepLinkNilIosUrl() {
        configureSDK()
        var json = validLinkJSON()
        json["ios_url"] = NSNull()
        mockResolveResponse(statusCode: 200, json: json)

        let exp = expectation(description: "completion")
        WarpLink.handleDeepLink(URL(string: "https://aplnk.to/abc123")!) { result in
            guard case .success(let deepLink) = result else {
                XCTFail("Expected success, got \(result)")
                exp.fulfill()
                return
            }
            XCTAssertNil(deepLink.deepLinkUrl)
            XCTAssertEqual(deepLink.destination, "https://example.com")
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    // MARK: - Helpers

    private func configureSDK() {
        // Mock handler that handles both validation and resolve requests
        HandleDeepLinkMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        WarpLink.configure(apiKey: testApiKey)
    }

    private func mockResolveResponse(statusCode: Int, json: [String: Any]) {
        HandleDeepLinkMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode,
                httpVersion: nil, headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: json)
            return (response, data)
        }
    }

    private func validLinkJSON() -> [String: Any] {
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
}
