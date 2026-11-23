import Foundation

extension WarpLink {

    /// Reads a Tether code from the clipboard now, and redeems it.
    ///
    /// Call this when your app decides the moment is right, usually the first
    /// screen after install. iOS may show its paste prompt, and the person
    /// can refuse it. Only text that is a WarpLink code is sent. Anything else
    /// stays on the device.
    ///
    /// - `.success(.matched(link))`: the code led to `link`. It is also cached
    ///   as `attributionResult`.
    /// - `.success(.noCode(reason))`: nothing usable was on the clipboard. No
    ///   request was sent, and `reason` is sent with the next attribution
    ///   request.
    /// - `.success(.unusable)`: a code was sent and led nowhere.
    /// - `.success(.test(receipt:))`: a test code. Nothing was recorded.
    /// - `.failure`: the code is invalid or expired, or the network failed.
    ///
    /// `completion` is always called on the main queue.
    ///
    /// The clipboard is cleared only after the server used the code, and only if
    /// it still holds what was read. Works in every `tetherReadMode`; the mode
    /// decides only what the SDK does by itself.
    public static func readTether(
        completion: @escaping (Result<TetherReadResult, WarpLinkError>) -> Void
    ) {
        let finish = { (result: Result<TetherReadResult, WarpLinkError>) in
            SDKEnvironment.deliver { completion(result) }
        }
        guard let context = referralContext() else {
            finish(.failure(.notConfigured))
            return
        }
        TetherServices.readQueue {
            switch TetherReader.read(TetherServices.clipboard) {
            case let .miss(reason):
                TetherServices.recordMiss(reason, mode: .onCall)
                finish(.success(.noCode(reason)))
            case let .code(claim):
                ReferralRedeemer.redeem(claim: claim, readMode: .onCall, context: context) { result, detail in
                    finish(TetherReadResult.make(result, detail: detail))
                }
            }
        }
    }

    /// The receipt of the last test code the server took, or nil. Show it on a
    /// test screen to prove the code arrived. It is forgotten when the app
    /// starts, and by `clearAttribution()`.
    public static var lastTetherTestReceipt: String? {
        TetherServices.testReceipt
    }
}
