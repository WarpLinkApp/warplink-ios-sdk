import XCTest
@testable import WarpLink

/// Answers for the deferred check suites that control the wall clock, the
/// install date and the app's foreground state.
enum CheckWire {

    static let validated: [String: Any] = ["valid": true, "domains": ["aplnk.to"]]
    static let noMatch: [String: Any] = ["matched": false]
    static let matched: [String: Any] = [
        "matched": true,
        "link_id": "link-deferred-1",
        "destination_url": "https://example.com/welcome",
        "match_type": "fingerprint",
        "match_confidence": 0.9,
    ]

    static func answer(
        _ body: [String: Any], status: Int = 200, for request: URLRequest
    ) -> (Data?, URLResponse?, Error?) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        return (try? JSONSerialization.data(withJSONObject: body), response, nil)
    }

    static let offline: (Data?, URLResponse?, Error?) = (nil, nil, URLError(.notConnectedToInternet))
}

/// Base for the suites about how often the SDK asks the server.
///
/// The SDK is synchronous (see `makeSDKSynchronous`), the wall clock and the
/// install date are fields the test moves, the app is always active unless a
/// test says otherwise, and storage is in memory and survives a `configure()`.
class CheckTrafficTestCase: XCTestCase {

    let liveKey = "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    let testKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    let deviceId = "11111111-1111-4111-8111-111111111111"
    let hour: TimeInterval = 3600
    let day: TimeInterval = 86_400

    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    var installedAt: Date?
    var installMarkers = InMemoryMarkerStore()
    var durableMarkers = InMemoryMarkerStore()
    private(set) var storage: Storage!

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        installedAt = clock
        installMarkers = InMemoryMarkerStore()
        durableMarkers = InMemoryMarkerStore()
        installEnvironment()
    }

    /// The app starts again: SDK state is gone, the clock, the install and what
    /// the SDK stored on disk are not.
    func relaunch() {
        WarpLink.reset()
        installEnvironment()
    }

    private func installEnvironment() {
        SDKEnvironment.now = { [unowned self] in clock }
        SDKEnvironment.installDate = { [unowned self] in installedAt }
        SDKEnvironment.whenActive = { $0() }
        SDKEnvironment.makeStorage = { [unowned self] environment in
            let name = "CheckTraffic-\(type(of: self))"
            let defaults = UserDefaults(suiteName: name)!
            if storage == nil { defaults.removePersistentDomain(forName: name) }
            let made = Storage(
                environment: environment, defaults: defaults,
                markerStore: durableMarkers, installMarkerStore: installMarkers
            )
            storage = made
            return made
        }
    }

    override func tearDown() {
        WarpLink.reset()
        storage = nil
        super.tearDown()
    }

    /// Configures the SDK with the first-launch check off. Needs the transport
    /// first, since the API client takes it at `configure()`.
    @discardableResult
    func configure(
        _ transport: InlineTransport, key: String? = nil, options: WarpLinkOptions = TestSupport.noAuto
    ) -> Storage {
        let foreground = SDKEnvironment.whenActive
        makeSDKSynchronous(transport)
        SDKEnvironment.whenActive = foreground
        SDKEnvironment.installDate = { [unowned self] in installedAt }
        WarpLink.configure(apiKey: key ?? liveKey, options: options)
        WarpLink.fingerprintCollector = FingerprintCollector(vendorIdentifier: { [deviceId] in deviceId })
        return storage
    }

    /// A transport that serves `/sdk/validate` and answers every match with `respond`.
    func serving(_ respond: @escaping (URLRequest) -> (Data?, URLResponse?, Error?)) -> InlineTransport {
        InlineTransport { request in
            request.url?.path.contains("/attribution/match") == true
                ? respond(request)
                : CheckWire.answer(CheckWire.validated, for: request)
        }
    }

    func serving(_ body: [String: Any], status: Int = 200) -> InlineTransport {
        serving { CheckWire.answer(body, status: status, for: $0) }
    }

    /// Runs one deferred check and returns what it answered.
    @discardableResult
    func check() -> Result<WarpLinkDeepLink?, WarpLinkError>? {
        let results = Results()
        WarpLink.checkDeferredDeepLink { results.append($0) }
        return results.all.first
    }

    func matchCount(_ transport: InlineTransport) -> Int {
        transport.requestCount(forPathContaining: "/attribution/match")
    }

    func matchBodies(_ transport: InlineTransport) -> [[String: Any]] {
        transport.bodies(forPathContaining: "/attribution/match")
    }

    func assertNoMatch(
        _ result: Result<WarpLinkDeepLink?, WarpLinkError>?, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .success(let link)? = result, link == nil else {
            return XCTFail("expected success(nil), got \(String(describing: result))", file: file, line: line)
        }
    }
}
