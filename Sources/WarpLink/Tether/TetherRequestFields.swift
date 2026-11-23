import Foundation

/// The fields Tether adds to a match request, written the same way for the
/// first-open request and for a redeem.
struct TetherRequestFields {

    let installationId: String
    var claim: TetherClaim?
    var readMode: TetherReadMode?
    var missReason: TetherMissReason?

    init(
        installationId: String,
        claim: TetherClaim? = nil,
        readMode: TetherReadMode? = nil,
        missReason: TetherMissReason? = nil
    ) {
        self.installationId = installationId
        self.claim = claim
        self.readMode = readMode
        self.missReason = missReason
    }

    var code: TetherCode? { claim?.code }

    /// The same request with no code, for the run that follows a test code or a
    /// refused one. The read mode and the miss reason stay: they describe how
    /// this install was read, not the code.
    func withoutCode() -> TetherRequestFields {
        TetherRequestFields(installationId: installationId, readMode: readMode, missReason: missReason)
    }

    /// Adds the fields to `body`. A prefixed code travels as `tether_code`; an
    /// unprefixed invitation travels as `recovery_token`, as before Tether.
    func write(to body: inout [String: Any]) {
        body["installation_id"] = installationId
        body["sdk_platform"] = TetherServices.sdkPlatform
        if let readMode = readMode {
            body["tether_read_mode"] = readMode.rawValue
        }
        if let missReason = missReason {
            body["tether_miss_reason"] = missReason.rawValue
        }
        switch code {
        case let .live(text)?, let .test(text)?: body["tether_code"] = text
        case let .invitation(token)?: body["recovery_token"] = token
        case nil: break
        }
    }
}
