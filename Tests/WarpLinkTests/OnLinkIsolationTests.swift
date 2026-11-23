import XCTest
@testable import WarpLink

/// A main-actor type, standing in for the router or view model an app calls
/// from `onLink`.
@MainActor
private final class Screen {
    private(set) var results: [Result<WarpLinkDeepLink?, WarpLinkError>] = []

    func show(_ result: Result<WarpLinkDeepLink?, WarpLinkError>) {
        results.append(result)
    }
}

/// `onLink` is a main-actor closure, so an app can call `@MainActor` code from
/// it. The SDK delivers on the main queue, which is where that code must run.
final class OnLinkIsolationTests: CheckTrafficTestCase {

    @MainActor
    private func configureWithScreen(_ screen: Screen) {
        configure(
            serving(CheckWire.matched),
            options: WarpLinkOptions(autoDeferredCheck: true, onLink: { screen.show($0) })
        )
    }

    @MainActor
    func testADeferredLinkReachesAMainActorHandler() {
        let screen = Screen()

        configureWithScreen(screen)

        guard case .success(let link?)? = screen.results.first else {
            return XCTFail("expected the matched link, got \(screen.results)")
        }
        XCTAssertEqual(link.linkId, "link-deferred-1")
        XCTAssertEqual(screen.results.count, 1)
    }

    func testTheHandlerRunsOnTheMainThreadWhenDeliveryIsLive() {
        SDKEnvironment.reset()
        let ranOnMain = Box<Bool>()
        let delivered = expectation(description: "onLink runs")
        let options = WarpLinkOptions(onLink: { _ in
            ranOnMain.value = Thread.isMainThread
            delivered.fulfill()
        })

        DispatchQueue.global().async { WarpLink.configure(apiKey: "wl_live_tooshort", options: options) }

        wait(for: [delivered], timeout: 2.0)
        XCTAssertEqual(ranOnMain.value, true)
    }

    @MainActor
    func testAKeyFormatErrorReachesAMainActorHandler() {
        let screen = Screen()
        makeSDKSynchronous(serving(CheckWire.noMatch))
        let options = WarpLinkOptions(onLink: { screen.show($0) })

        WarpLink.configure(apiKey: "wl_live_tooshort", options: options)

        guard case .failure(.invalidApiKeyFormat)? = screen.results.first else {
            return XCTFail("expected the key error, got \(screen.results)")
        }
    }

    // MARK: - Reading the stored handler

    func testTheStoredHandlerRunsAtOnceWhenCalledOnTheMainThread() {
        let calls = Box<Int>()
        calls.value = 0
        let options = WarpLinkOptions(onLink: { _ in calls.value = (calls.value ?? 0) + 1 })

        options.onLink?(.success(nil))

        XCTAssertEqual(calls.value, 1)
    }

    func testTheStoredHandlerHopsToTheMainThreadWhenCalledFromAnother() {
        let ranOnMain = Box<Bool>()
        let ran = expectation(description: "handler runs")
        let options = WarpLinkOptions(onLink: { _ in
            ranOnMain.value = Thread.isMainThread
            ran.fulfill()
        })

        DispatchQueue.global().async { options.onLink?(.success(nil)) }

        wait(for: [ran], timeout: 2.0)
        XCTAssertEqual(ranOnMain.value, true)
    }

    func testNoOnLinkStaysNil() {
        XCTAssertNil(WarpLinkOptions().onLink)
    }
}
