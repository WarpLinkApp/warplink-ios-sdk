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

final class APIClientTests: XCTestCase {

    private var client: APIClient!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        client = APIClient(
            apiKey: "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
            baseURL: "https://api.warplink.app/v1",
            session: session
        )
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testValidateApiKeySuccess200() {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.warplink.app/v1/sdk/validate")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let exp = expectation(description: "completion")
        client.validateApiKey { result in
            if case .success(let valid) = result {
                XCTAssertTrue(valid)
            } else {
                XCTFail("Expected success(true), got \(result)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testValidateApiKeyUnauthorized401() {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.warplink.app/v1/sdk/validate")!,
                statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let exp = expectation(description: "completion")
        client.validateApiKey { result in
            if case .success(let valid) = result {
                XCTAssertFalse(valid)
            } else {
                XCTFail("Expected success(false), got \(result)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testValidateApiKeyForbidden403() {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.warplink.app/v1/sdk/validate")!,
                statusCode: 403, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let exp = expectation(description: "completion")
        client.validateApiKey { result in
            if case .success(let valid) = result {
                XCTAssertFalse(valid)
            } else {
                XCTFail("Expected success(false), got \(result)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testValidateApiKeyNetworkError() {
        MockURLProtocol.requestHandler = { _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        }

        let exp = expectation(description: "completion")
        client.validateApiKey { result in
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

    func testValidateApiKeyRequestHeaders() {
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

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let exp = expectation(description: "completion")
        client.validateApiKey { _ in exp.fulfill() }
        waitForExpectations(timeout: 2)
    }
}
