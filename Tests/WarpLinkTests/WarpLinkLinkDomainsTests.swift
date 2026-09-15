import XCTest
@testable import WarpLink

/// Serves the resolve endpoint and refuses `/sdk/validate`, which is the shape
/// of the launch this whole feature exists for: the server's domain list is not
/// available (first launch, or offline), so the only domains the SDK can know
/// are the ones declared locally.
private final class DomainsMockProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        guard !path.contains("validate") else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        let body = try! JSONSerialization.data(withJSONObject: WarpLinkLinkDomainsTests.linkJSON)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// An Info.plist declaration, without an app target to put one in.
private struct StubDeclaration: LinkDomainDeclaring {
    let domains: [String]
    func declaredLinkDomains() -> [String] { domains }
}

final class WarpLinkLinkDomainsTests: XCTestCase {

    private let apiKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    private let customDomainURL = URL(string: "https://links.acme.com/abc123")!

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        URLProtocol.registerClass(DomainsMockProtocol.self)
        // A pristine device: no domain list cached from an earlier launch, and
        // no key-validation cache that would skip the (refused) validate call.
        pristineStorage().clearAll()
    }

    override func tearDown() {
        URLProtocol.unregisterClass(DomainsMockProtocol.self)
        // The suite writes to the shared defaults, so it cleans up after itself
        // rather than leaving a domain cache for the next suite to inherit.
        pristineStorage().clearAll()
        WarpLink.reset()
        super.tearDown()
    }

    // MARK: - The hole this closes

    func testCustomDomainIsRejectedWhenNothingIsDeclared() {
        // The bug, stated as a test: with no declaration and no server answer,
        // the link is handed back to the host app, which has no route for it.
        WarpLink.configure(apiKey: apiKey, options: TestSupport.noAuto)
        XCTAssertFalse(WarpLink.knownDomains().contains("links.acme.com"))
    }

    // conformance: WL-S08
    func testDomainDeclaredInOptionsResolvesOnTheFirstLaunch() {
        let box = Box<Result<WarpLinkDeepLink?, WarpLinkError>>()
        let exp = expectation(description: "onLink")
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeferredCheck: false,
            linkDomains: ["links.acme.com"],
            onLink: { result in box.value = result; exp.fulfill() }
        ))

        // Synchronous: no await between configure() and the link arriving.
        XCTAssertTrue(WarpLink.open(customDomainURL))
        waitForExpectations(timeout: 2)

        guard case .success(let link?) = box.value else {
            return XCTFail("Expected a resolved link, got \(String(describing: box.value))")
        }
        XCTAssertEqual(link.linkId, "550e8400-e29b-41d4-a716-446655440000")
    }

    // conformance: WL-S08
    func testDomainDeclaredInInfoPlistResolvesOnTheFirstLaunch() {
        WarpLink.domainDeclarationSource = StubDeclaration(domains: ["links.acme.com"])
        WarpLink.configure(apiKey: apiKey, options: TestSupport.noAuto)

        XCTAssertTrue(WarpLink.knownDomains().contains("links.acme.com"))
        XCTAssertTrue(customDomainURL.isWarpLinkUniversalLink(domains: WarpLink.knownDomains()))
    }

    // MARK: - The union

    func testDeclaredDomainsAreNormalized() {
        WarpLink.domainDeclarationSource = StubDeclaration(domains: ["  HTTPS://Plist.Acme.Com/  "])
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeepLinkHandling: false,
            autoDeferredCheck: false,
            linkDomains: ["https://Links.Acme.Com/"]
        ))

        XCTAssertTrue(WarpLink.knownDomains().isSuperset(of: ["links.acme.com", "plist.acme.com"]))
    }

    func testDefaultDomainSurvivesADeclaration() {
        // Declaring a custom domain adds to the set; it never replaces aplnk.to,
        // which every org's links can still use.
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeepLinkHandling: false,
            autoDeferredCheck: false,
            linkDomains: ["links.acme.com"]
        ))
        XCTAssertTrue(WarpLink.knownDomains().contains("aplnk.to"))
    }

    func testUndeclaredDomainIsStillRejected() {
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeepLinkHandling: false,
            autoDeferredCheck: false,
            linkDomains: ["links.acme.com"]
        ))
        XCTAssertFalse(WarpLink.knownDomains().contains("links.evil.com"))
    }

    func testServerDomainsDoNotEvictDeclaredDomains() {
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeepLinkHandling: false,
            autoDeferredCheck: false,
            linkDomains: ["links.acme.com"]
        ))

        // The validate response lands later and lists a different domain. The
        // declared one has to survive it: the server list is a supplement, and
        // a developer who declared a domain did so because it is theirs.
        WarpLink.applyServerDomains(["from.server.com"], storage: pristineStorage())

        XCTAssertTrue(WarpLink.knownDomains().isSuperset(of: [
            "aplnk.to", "links.acme.com", "from.server.com",
        ]))
    }

    func testCachedServerDomainsApplyAtConfigure() {
        let storage = pristineStorage()
        storage.cachedDomains = ["Cached.Acme.Com"]

        WarpLink.configure(apiKey: apiKey, options: TestSupport.noAuto)

        // Cached under the same UserDefaults the SDK's own Storage reads, and
        // folded on the way in like every other source.
        XCTAssertTrue(WarpLink.knownDomains().contains("cached.acme.com"))
    }

    func testResetClearsDeclaredDomains() {
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeepLinkHandling: false,
            autoDeferredCheck: false,
            linkDomains: ["links.acme.com"]
        ))
        WarpLink.reset()
        XCTAssertEqual(WarpLink.knownDomains(), ["aplnk.to"])
    }

    // MARK: - Helpers

    /// A `Storage` over the same defaults the SDK configures itself with, but
    /// with in-memory marker stores so no test touches the real Keychain.
    private func pristineStorage() -> Storage {
        Storage(
            defaults: .standard,
            markerStore: InMemoryMarkerStore(),
            installMarkerStore: InMemoryMarkerStore()
        )
    }

    static let linkJSON: [String: Any] = [
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "slug": "abc123",
        "domain": "links.acme.com",
        "destination_url": "https://example.com",
        "ios_url": "myapp://page",
        "ios_fallback_url": NSNull(),
        "custom_params": ["promo": "summer"],
        "created_at": "2026-01-01T00:00:00.000Z",
    ]
}
