import XCTest
@testable import WarpLink

/// `configure()` with the same key and equal options keeps the live session and
/// its running check. A different key or different options rebuilds, as before.
final class ConfigureReuseTests: CheckTrafficTestCase {

    private let otherKey = "wl_live_z9y8x7w6v5u4t3s2r1q0p9o8n7m6l5k4"

    private func holdingTransport() -> CancellingTransport {
        let held = CancellingTransport(holdingPathContaining: "/attribution/match")
        SDKEnvironment.makeTransport = { held }
        SDKEnvironment.deliver = { $0() }
        SDKEnvironment.schedule = { _, work in work() }
        return held
    }

    private func startHeldCheck(_ held: CancellingTransport) {
        WarpLink.configure(apiKey: liveKey, options: TestSupport.noAuto)
        WarpLink.fingerprintCollector = FingerprintCollector(vendorIdentifier: { [deviceId] in deviceId })
        WarpLink.checkDeferredDeepLink { _ in }
        XCTAssertEqual(held.held.count, 1)
    }

    // conformance: WL-S70

    func testTheSameKeyAndOptionsKeepTheRunningCheck() {
        let held = holdingTransport()
        startHeldCheck(held)
        let generation = WarpLink.deferredCheckGeneration
        let client = WarpLink.apiClient
        let kept = storage

        WarpLink.configure(apiKey: liveKey, options: TestSupport.noAuto)

        XCTAssertFalse(held.held[0].cancelled, "the running request is not stopped")
        XCTAssertEqual(WarpLink.deferredCheckGeneration, generation)
        XCTAssertTrue(WarpLink.isCheckInFlight)
        XCTAssertTrue(WarpLink.apiClient === client)
        XCTAssertTrue(WarpLink.storage === kept)
    }

    // conformance: WL-S70

    func testAnotherKeyRebuildsTheSession() {
        let held = holdingTransport()
        startHeldCheck(held)
        let generation = WarpLink.deferredCheckGeneration

        WarpLink.configure(apiKey: otherKey, options: TestSupport.noAuto)

        XCTAssertTrue(held.held[0].cancelled)
        XCTAssertGreaterThan(WarpLink.deferredCheckGeneration, generation)
    }

    // conformance: WL-S70

    func testDifferentOptionsRebuildTheSession() {
        let variants = [
            WarpLinkOptions(debugLogging: true, autoDeferredCheck: false),
            WarpLinkOptions(apiEndpoint: "https://other.example.com/v1", autoDeferredCheck: false),
            WarpLinkOptions(autoDeepLinkHandling: true, autoDeferredCheck: false),
            WarpLinkOptions(autoDeferredCheck: true),
            WarpLinkOptions(autoDeferredCheck: false, linkDomains: ["links.example.com"]),
            WarpLinkOptions(autoDeferredCheck: false, tetherReadMode: .onCall),
        ]
        for variant in variants {
            relaunch()
            installMarkers = InMemoryMarkerStore()
            let held = holdingTransport()
            startHeldCheck(held)

            WarpLink.configure(apiKey: liveKey, options: variant)

            XCTAssertTrue(held.held[0].cancelled, "\(variant) must rebuild")
        }
    }

    func testANewOnLinkReplacesTheOldOneWithoutARebuild() {
        let first = Counter()
        let second = Counter()
        let held = holdingTransport()
        WarpLink.configure(
            apiKey: liveKey, options: WarpLinkOptions(autoDeferredCheck: false, onLink: { _ in first.increment() })
        )
        WarpLink.fingerprintCollector = FingerprintCollector(vendorIdentifier: { [deviceId] in deviceId })
        WarpLink.checkDeferredDeepLink { _ in }

        WarpLink.configure(
            apiKey: liveKey, options: WarpLinkOptions(autoDeferredCheck: false, onLink: { _ in second.increment() })
        )
        WarpLink.dispatchToOnLink(.failure(.invalidURL))

        XCTAssertFalse(held.held[0].cancelled)
        XCTAssertEqual(first.value, 0)
        XCTAssertEqual(second.value, 1)
    }

    func testAReusedConfigureStartsNothingNew() {
        let transport = serving(CheckWire.noMatch)
        configure(transport, options: WarpLinkOptions())
        XCTAssertEqual(matchCount(transport), 1, "the first configure runs the automatic check")
        let validations = transport.requestCount(forPathContaining: "/sdk/validate")

        WarpLink.configure(apiKey: liveKey, options: WarpLinkOptions())

        XCTAssertEqual(matchCount(transport), 1)
        XCTAssertEqual(transport.requestCount(forPathContaining: "/sdk/validate"), validations)
    }

    func testAKeyThatFailsTheFormatCheckIsStillReportedWhenTheSessionIsLive() {
        configure(serving(CheckWire.noMatch))
        let reported = Results()

        WarpLink.configure(
            apiKey: "wl_live_short",
            options: WarpLinkOptions(autoDeferredCheck: false, onLink: { reported.append($0) })
        )

        guard case .failure(.invalidApiKeyFormat)? = reported.all.first else {
            return XCTFail("expected invalidApiKeyFormat, got \(String(describing: reported.all.first))")
        }
    }
}
