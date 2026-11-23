import XCTest
@testable import WarpLink

/// A link whose gate closed but which `onLink` never received, because the
/// process ended before the hop to the main queue. Only a link the gate marked
/// as awaiting delivery is handed over: an install from before the marker, with
/// a cached link and no marker, fires nothing.
final class RedeliveryTests: CheckTrafficTestCase {

    private let link = WarpLinkDeepLink(
        linkId: "lnk_lost", destination: "https://example.com/lost", isDeferred: true
    )

    private func configureWithSink(_ received: Results, auto: Bool = false) {
        configure(
            serving(CheckWire.matched),
            options: WarpLinkOptions(autoDeferredCheck: auto, onLink: { received.append($0) })
        )
    }

    private func seedClosedGate() {
        storage.markAttributionComplete()
        storage.cachedAttribution = link
    }

    func testAnUpgradedInstallWithACachedLinkAndNoMarkerFiresNothing() {
        let received = Results()
        configureWithSink(received)
        seedClosedGate()

        WarpLink.runAutoDeferredCheck()

        XCTAssertTrue(received.all.isEmpty)
    }

    func testALinkMarkedAsAwaitingDeliveryIsHandedOverOnce() {
        let received = Results()
        configureWithSink(received)
        seedClosedGate()
        storage.markAwaitingDelivery(link.routeIdentity)

        WarpLink.runAutoDeferredCheck()
        WarpLink.runAutoDeferredCheck()

        XCTAssertEqual(received.all.count, 1)
        guard case .success(let delivered?)? = received.all.first else {
            return XCTFail("expected the link, got \(String(describing: received.all.first))")
        }
        XCTAssertEqual(delivered.linkId, "lnk_lost")
        XCTAssertNil(storage.awaitingDeliveryRoute)
    }

    func testAProcessKilledBetweenTheGateAndOnLinkGetsTheLinkOnTheNextLaunch() {
        let lost = Results()
        // The first launch: the answer is saved, the hop to the main queue never runs.
        makeSDKSynchronous(serving(CheckWire.matched))
        SDKEnvironment.deliver = { _ in }
        WarpLink.configure(
            apiKey: liveKey, options: WarpLinkOptions(autoDeferredCheck: true, onLink: { lost.append($0) })
        )
        XCTAssertTrue(storage.isAttributionComplete)
        XCTAssertEqual(storage.awaitingDeliveryRoute, storage.cachedAttribution?.routeIdentity)
        XCTAssertNotNil(storage.awaitingDeliveryRoute)
        XCTAssertTrue(lost.all.isEmpty)

        relaunch()
        let received = Results()
        configureWithSink(received, auto: true)

        XCTAssertEqual(received.all.count, 1)
        XCTAssertNil(storage.awaitingDeliveryRoute)
    }

    func testANormalDeliveryClearsTheMarker() {
        let received = Results()
        configureWithSink(received, auto: true)

        XCTAssertEqual(received.all.count, 1)
        XCTAssertNil(storage.awaitingDeliveryRoute)
    }

    func testAManualOnlyAppLeavesNoMarker() {
        configure(serving(CheckWire.matched))
        check()

        XCTAssertNil(storage.awaitingDeliveryRoute)
    }

    func testAManualCheckThatGetsTheLinkAfterAFailedAutoCheckLeavesNoMarker() {
        var online = false
        let received = Results()
        configure(
            serving { request in
                online
                    ? CheckWire.answer(CheckWire.matched, for: request)
                    : CheckWire.offline
            },
            options: WarpLinkOptions(autoDeferredCheck: true, onLink: { received.append($0) })
        )
        XCTAssertFalse(storage.isAttributionComplete)

        online = true
        clock = clock.addingTimeInterval(day)
        let manual = check()

        guard case .success(let delivered?)? = manual else {
            return XCTFail("expected the link, got \(String(describing: manual))")
        }
        XCTAssertTrue(storage.isAttributionComplete)
        XCTAssertNil(storage.awaitingDeliveryRoute)
        // The failed auto check told `onLink` about its error. The link went to the manual caller only.
        XCTAssertFalse(received.all.contains { if case .success = $0 { return true } else { return false } })

        relaunch()
        let relaunched = Results()
        configureWithSink(relaunched, auto: true)

        XCTAssertTrue(relaunched.all.isEmpty, "the app already had \(delivered.linkId)")
    }

    func testAManualCheckThatHandsOverAMarkedLinkClearsTheMarker() {
        let received = Results()
        configureWithSink(received)
        seedClosedGate()
        storage.markAwaitingDelivery(link.routeIdentity)

        let manual = check()

        guard case .success(let delivered?)? = manual else {
            return XCTFail("expected the link, got \(String(describing: manual))")
        }
        XCTAssertEqual(delivered.linkId, "lnk_lost")
        XCTAssertNil(storage.awaitingDeliveryRoute)

        WarpLink.runAutoDeferredCheck()
        XCTAssertTrue(received.all.isEmpty)
    }
}
