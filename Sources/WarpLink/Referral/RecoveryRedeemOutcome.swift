import Foundation

/// The two answers a recovery redeem can end on without a failure worth
/// retrying. A refusal is final: the same token would be refused again, so it
/// travels as an outcome and the bounded call never retries it.
enum RecoveryRedeemOutcome {
    case answered(AttributionResponse)
    case refused(ReferralMessages.Refusal)
}
