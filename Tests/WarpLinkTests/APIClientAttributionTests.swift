import XCTest
@testable import WarpLink

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

final class APIClientAttributionTests: XCTestCase {

    private var client: APIClient!
    private var session: URLSession!

    private let testSignals = DeviceSignals(
        acceptLanguage: "en-US,en",
        screenWidth: 390,
        screenHeight: 844,
        timezoneOffset: -300,
        userAgent: "WarpLink-iOS/0.1.0"
    )

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

    func testSuccessfulMatchResponse() {
        let responseJson: [String: Any] = [
            "matched": true,
            "match_type": "probabilistic",
            "match_confidence": 0.85,
            "link_id": "abc-123",
            "deep_link_url": "myapp://content/42",
            "destination_url": "https://example.com/42",
            "custom_params": ["promo": "summer"],
            "install_id": "inst-456",
            "app_id": "app-789",
        ]
        mockResponse(statusCode: 200, json: responseJson)

        let exp = expectation(description: "completion")
        client.matchAttribution(
            signals: testSignals,
            sdkVersion: "0.1.0",
            deviceId: nil
        ) { result in
            switch result {
            case .success(let response):
                XCTAssertTrue(response.matched)
                XCTAssertEqual(response.matchType, "probabilistic")
                XCTAssertEqual(response.matchConfidence, 0.85)
                XCTAssertEqual(response.linkId, "abc-123")
                XCTAssertEqual(response.deepLinkUrl, "myapp://content/42")
                XCTAssertEqual(response.destinationUrl, "https://example.com/42")
                XCTAssertEqual(response.installId, "inst-456")
            case .failure(let error):
                XCTFail("Expected success, got \(error)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testRequestBodyContainsSignals() {
        MockURLProtocol.requestHandler = { request in
            let bodyData = request.httpBody ?? Data()
            let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]

            XCTAssertEqual(body?["accept_language"] as? String, "en-US,en")
            XCTAssertEqual(body?["screen_width"] as? Int, 390)
            XCTAssertEqual(body?["screen_height"] as? Int, 844)
            XCTAssertEqual(body?["timezone_offset"] as? Int, -300)
            XCTAssertEqual(body?["user_agent"] as? String, "WarpLink-iOS/0.1.0")
            XCTAssertEqual(body?["platform"] as? String, "ios")
            XCTAssertEqual(body?["fingerprint_version"] as? String, "enriched")
            XCTAssertEqual(body?["sdk_version"] as? String, "0.1.0")

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: ["matched": false])
            return (response, data)
        }

        let exp = expectation(description: "completion")
        client.matchAttribution(
            signals: testSignals,
            sdkVersion: "0.1.0",
            deviceId: nil
        ) { _ in exp.fulfill() }
        waitForExpectations(timeout: 2)
    }

    func testNoMatchResponse() {
        mockResponse(statusCode: 200, json: ["matched": false])

        let exp = expectation(description: "completion")
        client.matchAttribution(
            signals: testSignals,
            sdkVersion: "0.1.0",
            deviceId: nil
        ) { result in
            switch result {
            case .success(let response):
                XCTAssertFalse(response.matched)
                XCTAssertNil(response.matchType)
                XCTAssertNil(response.linkId)
            case .failure(let error):
                XCTFail("Expected success, got \(error)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testUnauthorized401() {
        mockResponse(statusCode: 401, json: [:])

        let exp = expectation(description: "completion")
        client.matchAttribution(
            signals: testSignals,
            sdkVersion: "0.1.0",
            deviceId: nil
        ) { result in
            if case .failure(let error) = result {
                if case .invalidApiKey = error {} else {
                    XCTFail("Expected invalidApiKey, got \(error)")
                }
            } else {
                XCTFail("Expected failure")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testServerError500() {
        mockResponse(statusCode: 500, json: [:])

        let exp = expectation(description: "completion")
        client.matchAttribution(
            signals: testSignals,
            sdkVersion: "0.1.0",
            deviceId: nil
        ) { result in
            if case .failure(let error) = result {
                if case .serverError(let code, _) = error {
                    XCTAssertEqual(code, 500)
                } else {
                    XCTFail("Expected serverError, got \(error)")
                }
            } else {
                XCTFail("Expected failure")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testNetworkError() {
        MockURLProtocol.requestHandler = { _ in
            throw NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorNotConnectedToInternet
            )
        }

        let exp = expectation(description: "completion")
        client.matchAttribution(
            signals: testSignals,
            sdkVersion: "0.1.0",
            deviceId: nil
        ) { result in
            if case .failure(let error) = result {
                if case .networkError = error {} else {
                    XCTFail("Expected networkError, got \(error)")
                }
            } else {
                XCTFail("Expected failure")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testDeviceIdExcludedWhenNil() {
        MockURLProtocol.requestHandler = { request in
            let bodyData = request.httpBody ?? Data()
            let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertNil(body?["device_id"], "device_id should not be in body when nil")

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: ["matched": false])
            return (response, data)
        }

        let exp = expectation(description: "completion")
        client.matchAttribution(
            signals: testSignals,
            sdkVersion: "0.1.0",
            deviceId: nil
        ) { _ in exp.fulfill() }
        waitForExpectations(timeout: 2)
    }

    func testFingerprintCollectorIdfvPropertyExists() {
        let collector = FingerprintCollector()
        // idfv returns String? — on macOS test environment it may be nil,
        // but the property must exist and return the correct type
        let idfv: String? = collector.idfv
        // If non-nil, it should be a valid UUID string format
        if let value = idfv {
            XCTAssertFalse(value.isEmpty)
            XCTAssertNotNil(UUID(uuidString: value), "IDFV should be a valid UUID")
        }
        // If nil, that's also valid (macOS test env, device restore, etc.)
    }

    func testDeviceIdIncludedWhenProvided() {
        MockURLProtocol.requestHandler = { request in
            let bodyData = request.httpBody ?? Data()
            let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertEqual(body?["device_id"] as? String, "test-device-id")

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: ["matched": false])
            return (response, data)
        }

        let exp = expectation(description: "completion")
        client.matchAttribution(
            signals: testSignals,
            sdkVersion: "0.1.0",
            deviceId: "test-device-id"
        ) { _ in exp.fulfill() }
        waitForExpectations(timeout: 2)
    }

    func testRequestURLAndMethod() {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.warplink.app/v1/attribution/match")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Type"),
                "application/json"
            )

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: ["matched": false])
            return (response, data)
        }

        let exp = expectation(description: "completion")
        client.matchAttribution(
            signals: testSignals,
            sdkVersion: "0.1.0",
            deviceId: nil
        ) { _ in exp.fulfill() }
        waitForExpectations(timeout: 2)
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
