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
        acceptLanguage: "en-US",
        timezoneOffset: -300,
        timezone: "America/Toronto"
    )

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        client = APIClient(
            apiKey: "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
            baseURL: "https://api.warplink.app/v1",
            transport: URLSessionTransport(session: session)
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
            deviceId: nil,
            isReinstall: false
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


    func testRequestBodySendsIANATimezoneName() {
        let exp = expectation(description: "request")
        MockURLProtocol.requestHandler = { request in
            let body = try JSONSerialization.jsonObject(
                with: request.resolvedHTTPBody ?? Data()
            ) as? [String: Any]
            XCTAssertEqual(body?["timezone"] as? String, "America/Toronto")
            // The offset stays on the wire for servers that predate zone matching.
            XCTAssertEqual(body?["timezone_offset"] as? Int, -300)
            XCTAssertEqual(body?["fingerprint_version"] as? String, "enriched_tz")
            exp.fulfill()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, try JSONSerialization.data(withJSONObject: ["matched": false]))
        }

        client.matchAttribution(
            signals: DeviceSignals(
                acceptLanguage: "en-US",
                timezoneOffset: -300,
                timezone: "America/Toronto"
            ),
            sdkVersion: "0.1.0",
            deviceId: nil,
            isReinstall: false
        ) { _ in }
        waitForExpectations(timeout: 2)
    }

    // conformance: WL-S20
    func testRequestFallsBackToOffsetVariantWithoutAZone() {
        // An unreadable IANA zone degrades on its own: the zone is dropped, the
        // variant downgrades to the offset one, every other signal still
        // travels, and the request is still sent rather than abandoned.
        let sent = expectation(description: "request sent")
        MockURLProtocol.requestHandler = { request in
            let body = try JSONSerialization.jsonObject(
                with: request.resolvedHTTPBody ?? Data()
            ) as? [String: Any] ?? [:]
            // Omitted, never sent as an empty value: the server would match on
            // "" as though it were a real zone.
            XCTAssertFalse(body.keys.contains("timezone"), "an unreadable zone must be omitted")
            XCTAssertEqual(body["fingerprint_version"] as? String, "enriched")
            // The signals that were readable still travel.
            XCTAssertEqual(body["accept_language"] as? String, "en-US")
            XCTAssertEqual(body["timezone_offset"] as? Int, -300)
            sent.fulfill()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, try JSONSerialization.data(withJSONObject: ["matched": false]))
        }

        let completed = expectation(description: "completion")
        client.matchAttribution(
            signals: DeviceSignals(
                acceptLanguage: "en-US",
                timezoneOffset: -300,
                timezone: ""
            ),
            sdkVersion: "0.1.0",
            deviceId: nil,
            isReinstall: false
        ) { _ in completed.fulfill() }
        waitForExpectations(timeout: 2)
    }

    // conformance: WL-S13
    func testRequestBodyContainsSignals() {
        MockURLProtocol.requestHandler = { request in
            let bodyData = request.resolvedHTTPBody ?? Data()
            let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]

            XCTAssertEqual(body?["accept_language"] as? String, "en-US")
            XCTAssertEqual(body?["timezone_offset"] as? Int, -300)
            XCTAssertEqual(body?["platform"] as? String, "ios")
            XCTAssertEqual(body?["timezone"] as? String, "America/Toronto")
            XCTAssertEqual(body?["fingerprint_version"] as? String, "enriched_tz")
            XCTAssertEqual(body?["sdk_version"] as? String, "0.1.0")
            XCTAssertEqual(body?["is_reinstall"] as? Bool, false)

            // Contract: these must NOT be sent in the attribution body.
            XCTAssertNil(body?["screen_width"], "screen_width must not be sent")
            XCTAssertNil(body?["screen_height"], "screen_height must not be sent")
            XCTAssertNil(body?["user_agent"], "user_agent must not be in the body")

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
            deviceId: nil,
            isReinstall: false
        ) { _ in exp.fulfill() }
        waitForExpectations(timeout: 2)
    }

    func testNoMatchResponse() {
        mockResponse(statusCode: 200, json: ["matched": false])

        let exp = expectation(description: "completion")
        client.matchAttribution(
            signals: testSignals,
            sdkVersion: "0.1.0",
            deviceId: nil,
            isReinstall: false
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

    // conformance: WL-S17
    func testExplicitJsonNullsDecodeToNil() {
        // Distinct from testNoMatchResponse, where the same keys are absent: here
        // the server sends each one as an explicit null, which must arrive as nil
        // and never as the text "null" or an empty string.
        let responseJson: [String: Any] = [
            "matched": true,
            "match_type": NSNull(),
            "link_id": NSNull(),
            "deep_link_url": NSNull(),
            "destination_url": NSNull(),
            "install_id": NSNull(),
        ]
        mockResponse(statusCode: 200, json: responseJson)

        let exp = expectation(description: "completion")
        client.matchAttribution(
            signals: testSignals,
            sdkVersion: "0.1.0",
            deviceId: nil,
            isReinstall: false
        ) { result in
            switch result {
            case .success(let response):
                XCTAssertTrue(response.matched)
                XCTAssertNil(response.matchType)
                XCTAssertNil(response.linkId)
                XCTAssertNil(response.deepLinkUrl)
                XCTAssertNil(response.destinationUrl)
                XCTAssertNil(response.installId)
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
            deviceId: nil,
            isReinstall: false
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
            deviceId: nil,
            isReinstall: false
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
            deviceId: nil,
            isReinstall: false
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

    func testReinstallFlagIsCarriedOnTheWire() {
        MockURLProtocol.requestHandler = { request in
            let bodyData = request.resolvedHTTPBody ?? Data()
            let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertEqual(body?["is_reinstall"] as? Bool, true)

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
            deviceId: nil,
            isReinstall: true
        ) { _ in exp.fulfill() }
        waitForExpectations(timeout: 2)
    }

    func testDeviceIdExcludedWhenNil() {
        MockURLProtocol.requestHandler = { request in
            let bodyData = request.resolvedHTTPBody ?? Data()
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
            deviceId: nil,
            isReinstall: false
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
            let bodyData = request.resolvedHTTPBody ?? Data()
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
            deviceId: "test-device-id",
            isReinstall: false
        ) { _ in exp.fulfill() }
        waitForExpectations(timeout: 2)
    }

    func testRequestBodyIncludesAppBundleId() {
        let identifiedClient = APIClient(
            apiKey: "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
            baseURL: "https://api.warplink.app/v1",
            transport: URLSessionTransport(session: session),
            bundleIdentifier: "com.example.myapp"
        )
        MockURLProtocol.requestHandler = { request in
            let bodyData = request.resolvedHTTPBody ?? Data()
            let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertEqual(body?["app_bundle_id"] as? String, "com.example.myapp")

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: ["matched": false])
            return (response, data)
        }

        let exp = expectation(description: "completion")
        identifiedClient.matchAttribution(
            signals: testSignals,
            sdkVersion: "0.1.0",
            deviceId: nil,
            isReinstall: false
        ) { _ in exp.fulfill() }
        waitForExpectations(timeout: 2)
    }

    func testAppBundleIdOmittedWhenNil() {
        let anonymousClient = APIClient(
            apiKey: "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
            baseURL: "https://api.warplink.app/v1",
            transport: URLSessionTransport(session: session),
            bundleIdentifier: nil
        )
        MockURLProtocol.requestHandler = { request in
            let bodyData = request.resolvedHTTPBody ?? Data()
            let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            // Omitted, never sent as null: the server treats an absent key as
            // "SDK too old to identify itself".
            XCTAssertNil(body?["app_bundle_id"], "app_bundle_id should be absent when nil")

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: ["matched": false])
            return (response, data)
        }

        let exp = expectation(description: "completion")
        anonymousClient.matchAttribution(
            signals: testSignals,
            sdkVersion: "0.1.0",
            deviceId: nil,
            isReinstall: false
        ) { _ in exp.fulfill() }
        waitForExpectations(timeout: 2)
    }

    func testAppBundleIdOmittedWhenEmpty() {
        // The server rejects an empty app_bundle_id, which would 400 the whole
        // request and lose the match. An unusable bundle ID degrades to the
        // org-wide lookup instead.
        let blankClient = APIClient(
            apiKey: "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
            baseURL: "https://api.warplink.app/v1",
            transport: URLSessionTransport(session: session),
            bundleIdentifier: ""
        )
        MockURLProtocol.requestHandler = { request in
            let bodyData = request.resolvedHTTPBody ?? Data()
            let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertNil(body?["app_bundle_id"], "app_bundle_id should be absent when empty")

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: ["matched": false])
            return (response, data)
        }

        let exp = expectation(description: "completion")
        blankClient.matchAttribution(
            signals: testSignals,
            sdkVersion: "0.1.0",
            deviceId: nil,
            isReinstall: false
        ) { _ in exp.fulfill() }
        waitForExpectations(timeout: 2)
    }

    func testBundleIdentifierDefaultsToMainBundle() {
        // `configure()` builds the client without passing a bundle identifier,
        // so the default must read the host app's own bundle.
        let defaulted = APIClient(
            apiKey: "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
            baseURL: "https://api.warplink.app/v1",
            transport: URLSessionTransport(session: session)
        )
        XCTAssertEqual(defaulted.bundleIdentifier, Bundle.main.bundleIdentifier)
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
            deviceId: nil,
            isReinstall: false
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
