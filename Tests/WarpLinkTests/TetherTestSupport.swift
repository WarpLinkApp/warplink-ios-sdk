import XCTest
@testable import WarpLink

/// A clipboard the test owns. It counts reads, so a test can prove the SDK read
/// nothing, and it bumps `changeCount` as the real one does.
final class FakeClipboard: TetherClipboard {
    var canRead = true
    var denied = false
    private(set) var changeCount = 1
    private(set) var text: String?
    private(set) var readCount = 0
    private(set) var clearCount = 0

    var hasStrings: Bool { text != nil }

    func readString() -> String? {
        readCount += 1
        return denied ? nil : text
    }

    func clear() {
        clearCount += 1
        text = nil
        changeCount += 1
    }

    /// Another app, or the person, puts text on the clipboard.
    func copy(_ value: String) {
        text = value
        changeCount += 1
    }
}

/// Answers for a match request that carries Tether.
enum TetherWire {

    static func matched(tether: [String: Any]?) -> [String: Any] {
        var body = ReferralWire.matched
        if let tether = tether { body["tether"] = tether }
        return body
    }

    static let accepted: [String: Any] = ["status": "accepted", "accepted": true]
    static let rejected: [String: Any] = ["status": "rejected", "accepted": false]
    static let notFound: [String: Any] = ["status": "not_found", "accepted": false]
    static let test: [String: Any] = [
        "status": "test", "accepted": false, "test": true, "test_receipt": "receipt-1",
    ]
}

/// Base for the Tether suites: a clipboard double, a read queue that runs
/// inline, and a configured SDK in a chosen read mode.
class TetherTestCase: ReferralTestCase {

    let clipboard = FakeClipboard()

    /// A live code that is valid at `now`.
    var liveCode: String { "wl1_" + liveToken }

    override func setUp() {
        super.setUp()
        TetherServices.clipboard = clipboard
        TetherServices.readQueue = { $0() }
    }

    /// Configures the SDK in `mode`, with the first-launch check off.
    @discardableResult
    func configure(
        _ transport: HTTPTransport,
        mode: TetherReadMode,
        onLink: (@Sendable (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void)? = nil
    ) -> Storage {
        makeSDKSynchronous(transport)
        WarpLink.configure(
            apiKey: apiKey,
            options: WarpLinkOptions(autoDeferredCheck: false, tetherReadMode: mode, onLink: onLink)
        )
        return useLocalStorage()
    }

    private func useLocalStorage() -> Storage {
        let name = "TetherStorage-\(type(of: self))"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        storage = Storage(
            defaults: defaults,
            markerStore: InMemoryMarkerStore(),
            installMarkerStore: InMemoryMarkerStore()
        )
        WarpLink.storage = storage
        return storage
    }

    /// Serves every match request with `body` and records what was sent.
    func answering(_ body: [String: Any], status: Int = 200) -> InlineTransport {
        transport { ReferralWire.answer(status, body, for: $0) }
    }

    /// What a paste control hands over: the text and the stamp at the tap.
    func paste(_ text: String?) -> (Result<WarpLinkDeepLink?, WarpLinkError>, ReferralRedeemer.Detail)? {
        let outcome = Box<(Result<WarpLinkDeepLink?, WarpLinkError>, ReferralRedeemer.Detail)>()
        WarpLink.redeemPasted(text: text, stamp: clipboard.changeCount) { result, detail in
            outcome.value = (result, detail)
        }
        return outcome.value
    }

    /// Runs the first-launch check and returns its result.
    func firstOpen() -> Result<WarpLinkDeepLink?, WarpLinkError>? {
        let results = Results()
        WarpLink.checkDeferredDeepLink { results.append($0) }
        return results.all.first
    }

    func lastMatchBody(_ transport: InlineTransport) throws -> [String: Any] {
        try XCTUnwrap(transport.lastBody(forPathContaining: "/attribution/match"))
    }
}
