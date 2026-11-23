import Foundation

/// What a Tether read ended on. A failure is a `WarpLinkError`, not a case.
public enum TetherReadResult: Sendable, Equatable {

    /// The code led to a link. It is also cached as `attributionResult`.
    case matched(WarpLinkDeepLink)

    /// No code was read, so nothing was sent. The reason is kept and sent with
    /// the next attribution request.
    case noCode(TetherMissReason)

    /// A code was sent and the server did not use it, or it led to no link.
    /// Let the person continue.
    case unusable

    /// A test code reached the server. Nothing was recorded. The receipt is
    /// also kept as `WarpLink.lastTetherTestReceipt`.
    case test(receipt: String?)
}

extension TetherReadResult {

    /// The result of a redeem run, as a read reports it. A run that matched
    /// nothing is `.unusable`, because a code was sent.
    static func make(
        _ result: Result<WarpLinkDeepLink?, WarpLinkError>, detail: ReferralRedeemer.Detail
    ) -> Result<TetherReadResult, WarpLinkError> {
        switch result {
        case let .failure(error): return .failure(error)
        case let .success(link?): return .success(.matched(link))
        case .success(nil):
            if let miss = detail.miss { return .success(.noCode(miss)) }
            guard let tether = detail.tether, tether.test else { return .success(.unusable) }
            return .success(.test(receipt: tether.testReceipt))
        }
    }
}
