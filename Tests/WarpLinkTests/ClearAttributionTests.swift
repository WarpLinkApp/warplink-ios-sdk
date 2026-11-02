import XCTest
@testable import WarpLink

/// `clearAttribution()` and the key environment `configure()` chooses, driven
/// through the public entry points with every store in memory.
final class ClearAttributionTests: XCTestCase {

    private let testKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    private let liveKey = "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    private let suiteName = "ClearAttributionTests"

    private var defaults: UserDefaults!
    private var deviceMarkers: InMemoryMarkerStore!
    private var installMarkers: InMemoryMarkerStore!
    private var pending: InMemoryPendingStore!

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        deviceMarkers = InMemoryMarkerStore()
        installMarkers = InMemoryMarkerStore()
        pending = InMemoryPendingStore()
    }

    override func tearDown() {
        ReferralServices.evidenceStore.clear()
        defaults.removePersistentDomain(forName: suiteName)
        WarpLink.reset()
        super.tearDown()
    }

    private func matchingTransport() -> InlineTransport {
        InlineTransport { request in
            let path = request.url?.path ?? ""
            if path.contains("/attribution/match") {
                return ReferralWire.answer(200, ReferralWire.matched, for: request)
            }
            return ReferralWire.answer(200, ["valid": true, "domains": []], for: request)
        }
    }

    /// Configures against `transport`, with storage shared by every
    /// environment so a leak between them would show.
    private func configure(
        _ key: String, _ transport: HTTPTransport, auto: Bool = false
    ) {
        makeSDKSynchronous(transport)
        SDKEnvironment.makeStorage = { [unowned self] environment in
            Storage(
                environment: environment, defaults: self.defaults,
                markerStore: self.deviceMarkers, installMarkerStore: self.installMarkers
            )
        }
        WarpLink.configure(
            apiKey: key, options: WarpLinkOptions(autoDeferredCheck: auto)
        )
    }

    private func checkDeferred() -> Result<WarpLinkDeepLink?, WarpLinkError>? {
        let outcome = Box<Result<WarpLinkDeepLink?, WarpLinkError>>()
        WarpLink.checkDeferredDeepLink { outcome.value = $0 }
        return outcome.value
    }

    private func matchRequests(_ transport: InlineTransport) -> Int {
        transport.requestCount(forPathContaining: "/attribution/match")
    }

    // MARK: - Not configured, and live

    func testBeforeConfigureItAnswersNotConfigured() {
        guard case .failure(.notConfigured) = WarpLink.clearAttribution() else {
            return XCTFail("expected notConfigured")
        }
    }

    // conformance: WL-S51
    func testWithALiveKeyItChangesNothing() {
        let transport = matchingTransport()
        configure(liveKey, transport)
        _ = checkDeferred()
        ReferralServices.evidenceStore.remember(installId: "install-1")

        guard case .success = WarpLink.clearAttribution() else { return XCTFail("expected success") }

        XCTAssertTrue(WarpLink.isAttributionComplete)
        XCTAssertEqual(WarpLink.attributionResult?.linkId, "link-1")
        XCTAssertEqual(ReferralServices.evidenceStore.evidence.installId, "install-1")
        XCTAssertEqual(matchRequests(transport), 1, "a live key sends no new check")
    }

    // MARK: - Test reset

    // conformance: WL-S50
    func testWithATestKeyItClearsAttributionAndSendsNothing() {
        let transport = matchingTransport()
        configure(testKey, transport)
        _ = checkDeferred()
        let before = transport.requests.count

        guard case .success = WarpLink.clearAttribution() else { return XCTFail("expected success") }

        XCTAssertFalse(WarpLink.isAttributionComplete)
        XCTAssertNil(WarpLink.attributionResult)
        XCTAssertEqual(transport.requests.count, before, "nothing is deleted on the server")
    }

    func testAfterTheResetTheNextCheckAsksTheServerAgain() {
        let transport = matchingTransport()
        configure(testKey, transport)
        _ = checkDeferred()
        WarpLink.clearAttribution()

        let result = checkDeferred()

        XCTAssertEqual(matchRequests(transport), 2)
        guard case let .success(link?) = result else { return XCTFail("expected a match") }
        XCTAssertEqual(link.linkId, "link-1")
    }

    func testWithAutomaticChecksOnTheResetSchedulesAFreshAttempt() {
        let transport = matchingTransport()
        configure(testKey, transport, auto: true)
        XCTAssertEqual(matchRequests(transport), 1)

        WarpLink.clearAttribution()

        XCTAssertEqual(matchRequests(transport), 2)
        XCTAssertTrue(WarpLink.isAttributionComplete)
    }

    func testItClearsTheHeldReferralInvitationAndEvidence() {
        configure(testKey, matchingTransport())
        ReferralServices.pendingStore = pending
        pending.record = PendingRedemption(token: "t", expiresAt: .distantFuture)
        ReferralServices.evidenceStore.remember(installId: "install-1")

        WarpLink.clearAttribution()

        XCTAssertNil(pending.load())
        XCTAssertNil(ReferralServices.evidenceStore.evidence.installId)
    }

    // MARK: - In flight

    func testACheckOnTheWireBeforeTheResetCannotRefillTheClearedState() {
        let gate = GatedTransport(
            holding: { $0.url?.path.contains("/attribution/match") == true },
            otherwise: { ReferralWire.answer(200, ["valid": true, "domains": []], for: $0) }
        )
        configure(testKey, gate)
        let outcome = Box<Result<WarpLinkDeepLink?, WarpLinkError>>()
        WarpLink.checkDeferredDeepLink { outcome.value = $0 }
        XCTAssertEqual(gate.held.count, 1)

        WarpLink.clearAttribution()
        gate.release(status: 200, body: ReferralWire.matched)

        XCTAssertFalse(WarpLink.isAttributionComplete)
        XCTAssertNil(WarpLink.attributionResult)
        XCTAssertNil(ReferralServices.evidenceStore.evidence.installId)
        guard case .success(nil)? = outcome.value else { return XCTFail("expected the silent no-op") }
    }

    // MARK: - Switching keys

    func testConfiguringTestThenLiveThenTestRestoresEachNamespace() {
        let transport = matchingTransport()
        configure(testKey, transport)
        _ = checkDeferred()
        ReferralServices.evidenceStore.remember(installId: "test-install")

        configure(liveKey, transport)
        XCTAssertFalse(WarpLink.isAttributionComplete, "live starts clean")
        XCTAssertNil(WarpLink.attributionResult)
        XCTAssertNil(ReferralServices.evidenceStore.evidence.installId)
        _ = checkDeferred()
        ReferralServices.evidenceStore.remember(installId: "live-install")

        configure(testKey, transport)
        XCTAssertTrue(WarpLink.isAttributionComplete)
        XCTAssertEqual(ReferralServices.evidenceStore.evidence.installId, "test-install")
        WarpLink.clearAttribution()

        configure(liveKey, transport)
        XCTAssertTrue(WarpLink.isAttributionComplete, "Test never cleared live")
        XCTAssertEqual(WarpLink.attributionResult?.linkId, "link-1")
        XCTAssertEqual(ReferralServices.evidenceStore.evidence.installId, "live-install")
        ReferralServices.evidenceStore.clear()
    }
}
