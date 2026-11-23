import XCTest
@testable import WarpLink

/// The reset races: a Test reset never reaches live state, no answer in flight
/// refills cleared state, and a reset that cannot finish says so.
final class ClearAttributionRaceTests: XCTestCase {

    private let testKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    private let liveKey = "wl_live_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    private let suiteName = "ClearAttributionRaceTests"

    private var defaults: UserDefaults!
    private var deviceMarkers: DurableMarkerStore = InMemoryMarkerStore()
    private var installMarkers: InstallMarkerStore = InMemoryMarkerStore()

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        ReferralServices.pendingStore = InMemoryPendingStore()
        ReferralServices.evidenceStore = ReferralEvidenceStore(defaults: defaults)
        ReferralServices.now = { Date(timeIntervalSince1970: 1_800_000_000) }
    }

    override func tearDown() {
        ReferralServices.evidenceStore.clear()
        defaults.removePersistentDomain(forName: suiteName)
        WarpLink.reset()
        super.tearDown()
    }

    private var redeemGate: GatedTransport {
        GatedTransport(
            holding: { request in
                let body = String(data: request.resolvedHTTPBody ?? Data(), encoding: .utf8) ?? ""
                return body.contains("recovery_token")
            },
            otherwise: { ReferralWire.answer(200, ["valid": true, "domains": []], for: $0) }
        )
    }

    private func configure(_ key: String, _ transport: HTTPTransport, debugLogging: Bool = false) {
        makeSDKSynchronous(transport)
        SDKEnvironment.makeStorage = { [unowned self] environment in
            Storage(
                environment: environment, defaults: self.defaults,
                markerStore: self.deviceMarkers, installMarkerStore: self.installMarkers
            )
        }
        WarpLink.configure(
            apiKey: key, options: WarpLinkOptions(debugLogging: debugLogging, autoDeferredCheck: false)
        )
    }

    private func startRedeem(_ results: Results) {
        let token = ReferralTokenFixture.token(expiresAt: 1_900_000_000)
        WarpLink.redeemInvitation(text: token) { results.append($0) }
    }

    // conformance: WL-S52
    func testAResetThatCannotDeleteAMarkerReportsFailure() {
        installMarkers = FailingMarkerStore()
        configure(testKey, redeemGate)

        guard case .failure(.decodingError(let cause)) = WarpLink.clearAttribution() else {
            return XCTFail("expected decodingError")
        }
        XCTAssertEqual(cause.localizedDescription, "Could not clear stored attribution data.")
    }

    func testStorageSaysWhenAMarkerSurvivesTheClear() {
        let storage = Storage(
            environment: .test, defaults: defaults,
            markerStore: InMemoryMarkerStore(), installMarkerStore: FailingMarkerStore()
        )

        XCTAssertFalse(storage.clearAttribution())
    }

    func testTheResetClearsReferralStateWhileHoldingTheSDKLock() {
        configure(testKey, redeemGate)
        var lockFreeDuringClear = false
        ReferralServices.pendingStore = HookedPendingStore {
            if WarpLink.lock.try() {
                lockFreeDuringClear = true
                WarpLink.lock.unlock()
            }
        }

        WarpLink.clearAttribution()

        XCTAssertFalse(
            lockFreeDuringClear,
            "a configure() could switch the referral stores before the reset clears them"
        )
    }

    func testAKeyChangeAfterTheResetLeavesLiveReferralStateAlone() {
        configure(testKey, redeemGate)
        configure(liveKey, redeemGate)
        ReferralServices.evidenceStore.remember(installId: "live-install")
        configure(testKey, redeemGate)
        ReferralServices.evidenceStore.remember(installId: "test-install")

        WarpLink.clearAttribution()
        configure(liveKey, redeemGate)

        XCTAssertEqual(ReferralServices.evidenceStore.evidence.installId, "live-install")
    }

    func testARedeemOnTheWireWhenTheResetRunsCannotRestoreAttribution() {
        let gate = redeemGate
        configure(testKey, gate)
        let results = Results()
        startRedeem(results)
        XCTAssertEqual(gate.held.count, 1)

        WarpLink.clearAttribution()
        gate.release(status: 200, body: ReferralWire.matched)

        XCTAssertFalse(WarpLink.isAttributionComplete)
        XCTAssertNil(WarpLink.attributionResult)
        XCTAssertNil(ReferralServices.evidenceStore.evidence.installId)
        guard case .success(nil)? = results.all.first else { return XCTFail("expected the silent no-op") }
    }

    func testAReconfigureWithTheSameKeyOrphansARedeemOnTheWire() {
        let gate = redeemGate
        configure(testKey, gate)
        let results = Results()
        startRedeem(results)
        let epochBefore = ReferralServices.epoch

        // Same key, other options: a new session. The same options would keep this one.
        configure(testKey, gate, debugLogging: true)
        gate.release(status: 200, body: ReferralWire.matched)

        XCTAssertGreaterThan(ReferralServices.epoch, epochBefore)
        XCTAssertFalse(WarpLink.isAttributionComplete)
        XCTAssertNil(ReferralServices.evidenceStore.evidence.installId)
        guard case .success(nil)? = results.all.first else { return XCTFail("expected the silent no-op") }
    }
}

/// A pending store whose `clear()` runs a hook first, to land another call at
/// the exact point a reset is clearing.
private final class HookedPendingStore: ReferralPendingStore {
    private let onClear: () -> Void

    init(onClear: @escaping () -> Void) { self.onClear = onClear }

    func load() -> PendingRedemption? { nil }

    @discardableResult
    func save(_ record: PendingRedemption) -> Bool { true }

    func clear() { onClear() }
}
