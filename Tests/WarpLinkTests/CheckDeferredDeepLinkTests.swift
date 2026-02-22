import XCTest
@testable import WarpLink

private class DeferredMockProtocol: URLProtocol {
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

final class CheckDeferredDeepLinkTests: XCTestCase {

    private let testApiKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        testDefaults = UserDefaults(suiteName: "CheckDeferredDeepLinkTests")!
        testDefaults.removePersistentDomain(forName: "CheckDeferredDeepLinkTests")
        URLProtocol.registerClass(DeferredMockProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(DeferredMockProtocol.self)
        DeferredMockProtocol.requestHandler = nil
        testDefaults.removePersistentDomain(forName: "CheckDeferredDeepLinkTests")
        WarpLink.reset()
        super.tearDown()
    }

    // MARK: - Tests

    func testNotConfiguredReturnsError() {
        let exp = expectation(description: "completion")
        WarpLink.checkDeferredDeepLink { result in
            if case .failure(let error) = result, case .notConfigured = error {
                // Expected
            } else {
                XCTFail("Expected notConfigured, got \(result)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testFirstLaunchSuccessfulMatch() {
        configureWithMockStorage()
        mockAttributionResponse(matched: true)

        let exp = expectation(description: "completion")
        WarpLink.checkDeferredDeepLink { result in
            guard case .success(let deepLink) = result, let deepLink = deepLink else {
                XCTFail("Expected matched deep link, got \(result)")
                exp.fulfill()
                return
            }
            XCTAssertTrue(deepLink.isDeferred)
            XCTAssertEqual(deepLink.linkId, "link-abc-123")
            XCTAssertEqual(deepLink.destination, "https://example.com/42")
            XCTAssertEqual(deepLink.deepLinkUrl, "myapp://content/42")
            XCTAssertEqual(deepLink.matchType, .probabilistic)
            XCTAssertEqual(deepLink.matchConfidence, 0.85)
            XCTAssertEqual(deepLink.customParams["promo"] as? String, "summer")
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testFirstLaunchNoMatch() {
        configureWithMockStorage()
        mockAttributionResponse(matched: false)

        let exp = expectation(description: "completion")
        WarpLink.checkDeferredDeepLink { result in
            guard case .success(let deepLink) = result else {
                XCTFail("Expected success, got \(result)")
                exp.fulfill()
                return
            }
            XCTAssertNil(deepLink)
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testFirstLaunchNetworkError() {
        configureWithMockStorage()
        DeferredMockProtocol.requestHandler = { _ in
            throw NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorNotConnectedToInternet
            )
        }

        let exp = expectation(description: "completion")
        WarpLink.checkDeferredDeepLink { result in
            if case .failure(let error) = result, case .networkError = error {
                // Expected
            } else {
                XCTFail("Expected networkError, got \(result)")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testSecondLaunchReturnsCachedMatch() {
        configureWithMockStorage()
        mockAttributionResponse(matched: true)

        // First call — triggers API and caches
        let firstExp = expectation(description: "first call")
        WarpLink.checkDeferredDeepLink { _ in firstExp.fulfill() }
        waitForExpectations(timeout: 2)

        // Track whether a network request is made on second call
        var networkRequestMade = false
        DeferredMockProtocol.requestHandler = { request in
            // Only count attribution match requests, not validation
            if request.url?.path.contains("attribution") == true {
                networkRequestMade = true
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: ["matched": false])
            return (response, data)
        }

        // Second call — should use cache
        let secondExp = expectation(description: "second call")
        WarpLink.checkDeferredDeepLink { result in
            guard case .success(let deepLink) = result, let deepLink = deepLink else {
                XCTFail("Expected cached deep link, got \(result)")
                secondExp.fulfill()
                return
            }
            XCTAssertTrue(deepLink.isDeferred)
            XCTAssertEqual(deepLink.linkId, "link-abc-123")
            secondExp.fulfill()
        }
        waitForExpectations(timeout: 2)
        XCTAssertFalse(networkRequestMade, "Should not make network request on second launch")
    }

    func testSecondLaunchReturnsNilWhenNoMatch() {
        configureWithMockStorage()
        mockAttributionResponse(matched: false)

        // First call — no match, no cache
        let firstExp = expectation(description: "first call")
        WarpLink.checkDeferredDeepLink { _ in firstExp.fulfill() }
        waitForExpectations(timeout: 2)

        // Second call — should return nil without API call
        var networkRequestMade = false
        DeferredMockProtocol.requestHandler = { request in
            if request.url?.path.contains("attribution") == true {
                networkRequestMade = true
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: ["matched": false])
            return (response, data)
        }

        let secondExp = expectation(description: "second call")
        WarpLink.checkDeferredDeepLink { result in
            guard case .success(let deepLink) = result else {
                XCTFail("Expected success, got \(result)")
                secondExp.fulfill()
                return
            }
            XCTAssertNil(deepLink)
            secondExp.fulfill()
        }
        waitForExpectations(timeout: 2)
        XCTAssertFalse(networkRequestMade, "Should not make network request on second launch")
    }

    // MARK: - Helpers

    private func configureWithMockStorage() {
        // First configure normally (with mock protocol intercepting validation)
        DeferredMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        WarpLink.configure(apiKey: testApiKey)

        // Replace storage with one using ephemeral UserDefaults
        WarpLink.storage = Storage(defaults: testDefaults)
    }

    private func mockAttributionResponse(matched: Bool) {
        DeferredMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil
            )!
            var json: [String: Any] = ["matched": matched]
            if matched {
                json["match_type"] = "probabilistic"
                json["match_confidence"] = 0.85
                json["link_id"] = "link-abc-123"
                json["deep_link_url"] = "myapp://content/42"
                json["destination_url"] = "https://example.com/42"
                json["custom_params"] = ["promo": "summer"]
                json["install_id"] = "inst-456"
            }
            let data = try JSONSerialization.data(withJSONObject: json)
            return (response, data)
        }
    }
}
