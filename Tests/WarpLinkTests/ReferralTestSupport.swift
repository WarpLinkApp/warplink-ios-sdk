import XCTest
@testable import WarpLink

/// A pending store that lives in memory, so no test touches the Keychain.
final class InMemoryPendingStore: ReferralPendingStore {
    var record: PendingRedemption?
    private(set) var saved: [PendingRedemption] = []

    func load() -> PendingRedemption? { record }

    @discardableResult
    func save(_ record: PendingRedemption) -> Bool {
        saved.append(record)
        self.record = record
        return true
    }

    func clear() { record = nil }
}

/// Answers for the referral routes, as the server writes them.
enum ReferralWire {

    static func answer(
        _ status: Int, _ body: [String: Any], for request: URLRequest
    ) -> (Data?, URLResponse?, Error?) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        return (try? JSONSerialization.data(withJSONObject: body), response, nil)
    }

    static func refusal(
        _ code: String, for request: URLRequest
    ) -> (Data?, URLResponse?, Error?) {
        answer(400, ["error": ["code": code, "message": "server wording"]], for: request)
    }

    /// The 503 the server answers while a just-issued token's payload has not
    /// reached this region yet.
    static func pendingAnswer(for request: URLRequest) -> (Data?, URLResponse?, Error?) {
        answer(
            503,
            ["error": ["code": "RECOVERY_TOKEN_PENDING", "message": "server wording"]],
            for: request
        )
    }

    static let matched: [String: Any] = [
        "matched": true,
        "match_type": "deterministic",
        "match_guaranteed": true,
        "link_id": "link-1",
        "destination_url": "https://example.com/welcome",
        "deep_link_url": "myapp://welcome",
        "custom_params": ["plan": "pro"],
        "install_id": "6f1c1f0e-5a0e-4f3e-9d5b-0a1f1d3c9b11",
        "attribution_id": "attr-1",
        "match_method": "install_token",
        "evidence_class": "exact",
        "replay_state": "original",
        "captured_params": ["utm_source": "friend"],
        "tapped_at": "2026-10-20T10:00:00.000Z",
    ]
}

/// Base for the referral suites: stores that touch nothing outside the test,
/// a clock the test owns, and a configured SDK.
class ReferralTestCase: XCTestCase {

    let apiKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    let pending = InMemoryPendingStore()
    var storage: Storage!
    var evidenceDefaults: UserDefaults!
    var now = Date(timeIntervalSince1970: 1_800_000_000)

    /// An invitation that is valid at `now`.
    var liveToken: String { ReferralTokenFixture.token(expiresAt: 1_900_000_000) }

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        pending.record = nil
        let suite = "ReferralTests-\(type(of: self))"
        evidenceDefaults = UserDefaults(suiteName: suite)!
        evidenceDefaults.removePersistentDomain(forName: suite)
        ReferralServices.pendingStore = pending
        ReferralServices.evidenceStore = ReferralEvidenceStore(defaults: evidenceDefaults)
        ReferralServices.now = { [unowned self] in self.now }
    }

    override func tearDown() {
        WarpLink.reset()
        super.tearDown()
    }

    /// Asserts `error` is the user-facing failure for `refusal`: the status the
    /// server refuses a token with, and that refusal's message.
    func assertIsRefusal(
        _ error: WarpLinkError, _ refusal: ReferralMessages.Refusal,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case let .serverError(status, message) = error else {
            return XCTFail("got \(error)", file: file, line: line)
        }
        XCTAssertEqual(status, ReferralMessages.refusalStatus, file: file, line: line)
        XCTAssertEqual(message, refusal.message, file: file, line: line)
    }

    /// Configures the SDK against `transport`, with storage that is private to
    /// this test. The real one would close this install's gate for later runs.
    @discardableResult
    func configure(
        _ transport: HTTPTransport,
        onLink: (@Sendable (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void)? = nil
    ) -> Storage {
        makeSDKSynchronous(transport)
        WarpLink.configure(
            apiKey: apiKey,
            options: WarpLinkOptions(autoDeferredCheck: false, onLink: onLink)
        )
        let defaults = UserDefaults(suiteName: "ReferralStorage-\(type(of: self))")!
        defaults.removePersistentDomain(forName: "ReferralStorage-\(type(of: self))")
        storage = Storage(
            defaults: defaults,
            markerStore: InMemoryMarkerStore(),
            installMarkerStore: InMemoryMarkerStore()
        )
        WarpLink.storage = storage
        return storage
    }

    /// Serves key validation, and `route` for the referral paths.
    func transport(
        route: @escaping (URLRequest) -> (Data?, URLResponse?, Error?)
    ) -> InlineTransport {
        InlineTransport { request in
            let path = request.url?.path ?? ""
            if path.contains("/attribution/match") || path.contains("/referrals/") {
                return route(request)
            }
            return ReferralWire.answer(200, ["valid": true, "domains": ["aplnk.to"]], for: request)
        }
    }

    func redeem(_ text: String) -> Result<WarpLinkDeepLink?, WarpLinkError>? {
        let results = Results()
        WarpLink.redeemInvitation(text: text) { results.append($0) }
        return results.all.first
    }
}
