import Foundation

/// Tether on the first-launch attribution request: what rides with it, and what
/// its answer means for the clipboard.
extension WarpLink {

    /// The read mode set in the options. `.pasteButton` before `configure()`.
    static var tetherReadMode: TetherReadMode {
        lock.lock(); defer { lock.unlock() }
        return options?.tetherReadMode ?? .pasteButton
    }

    /// The Tether fields for the first-launch request.
    ///
    /// Only `.automatic` reads the clipboard, once, on the read queue because
    /// the read may wait on the system paste prompt. Any other mode reads
    /// nothing, and sends the miss an earlier paste or `readTether` left, if
    /// there is one. Every request names the configured read mode.
    static func firstOpenTetherFields(
        store: Storage, mode: TetherReadMode, ready: @escaping (TetherRequestFields) -> Void
    ) {
        let installationId = store.installationId
        guard mode == .automatic else {
            var fields = TetherRequestFields(installationId: installationId, readMode: mode)
            if let miss = TetherServices.takeMiss() {
                fields.readMode = miss.mode
                fields.missReason = miss.reason
            }
            ready(fields)
            return
        }
        TetherServices.readQueue {
            var fields = TetherRequestFields(installationId: installationId, readMode: .automatic)
            switch TetherReader.read(TetherServices.clipboard) {
            case let .code(claim): fields.claim = claim
            case let .miss(reason): fields.missReason = reason
            }
            ready(fields)
        }
    }

    /// Acts on the answer to a request that carried `sent`: empties the clipboard
    /// once the server used the code, and keeps a test receipt.
    ///
    /// Returns the fields for a second request without the code when this
    /// answer must not be this install's: a test code records nothing, so the
    /// check has not happened yet, and a refusal in the 4xx range means the
    /// request never reached the signals. A 429 is no refusal of the code, so
    /// it is never resent without it. Returns nil when the answer stands.
    static func settleTether(
        _ result: Result<AttributionResponse, WarpLinkError>, sent: TetherRequestFields
    ) -> TetherRequestFields? {
        guard sent.code != nil else { return nil }
        switch result {
        case let .success(response):
            guard let tether = response.tether else { return nil }
            if sent.claim?.isUsed(by: tether) == true {
                sent.claim?.clearIfHeld(on: TetherServices.clipboard)
            }
            guard tether.test else { return nil }
            TetherServices.recordTestReceipt(tether.testReceipt)
            return sent.withoutCode()
        case let .failure(.serverError(statusCode, _)) where (400..<500).contains(statusCode) && statusCode != RateLimit.statusCode:
            return sent.withoutCode()
        case .failure:
            return nil
        }
    }
}
