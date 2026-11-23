import Foundation

/// How a redeem run ends: the answer is applied, or the record is settled.
extension ReferralRedeemer {

    /// Checks the epoch and applies the answer in one hold of the SDK lock, so a
    /// key change or `clearAttribution()` cannot land between the two. An answer
    /// that belongs to state that is gone applies nothing.
    static func finishRun(
        _ result: Result<RecoveryRedeemOutcome, WarpLinkError>,
        record: PendingRedemption,
        claim: TetherClaim,
        epoch: Int,
        readMode: TetherReadMode,
        pendingRetried: Bool,
        context: Context,
        completion: @escaping Report
    ) {
        WarpLink.lock.lock()
        guard ReferralServices.epoch == epoch else {
            WarpLink.lock.unlock()
            ReferralServices.endRedeem()
            completion(.success(nil), Detail())
            return
        }
        let finished = finish(result, record: record, claim: claim, context: context)
        let clearGeneration = context.store.attributionClearGeneration
        WarpLink.lock.unlock()
        finished.settle()
        if !pendingRetried, let wait = TetherPending.wait(for: finished.tether) {
            retryPending(
                after: wait, record: record, claim: claim, epoch: epoch,
                readMode: readMode, context: context, completion: completion
            )
            return
        }
        clearClipboard(claim, after: finished.tether)
        ReferralServices.endRedeem()
        var detail = Detail(tether: finished.tether)
        detail.clearGeneration = clearGeneration
        if finished.upgradesRoute, case let .success(exact?) = finished.outcome {
            WarpLink.dispatchAttributionToOnLink(.success(exact), ifGeneration: clearGeneration)
            detail.routedToOnLink = true
        }
        completion(finished.outcome, detail)
    }

    /// A pending code is not final, and its record stays. Waits, then sends the
    /// same request once more, unless the SDK state changed in the meantime.
    private static func retryPending(
        after wait: TimeInterval,
        record: PendingRedemption,
        claim: TetherClaim,
        epoch: Int,
        readMode: TetherReadMode,
        context: Context,
        completion: @escaping Report
    ) {
        SDKEnvironment.schedule(wait) {
            guard ReferralServices.epoch == epoch else {
                ReferralServices.endRedeem()
                completion(.success(nil), Detail())
                return
            }
            // The saved record decides: a newer paste may have replaced this
            // code during the wait, and the old code must not be redeemed.
            guard let saved = ReferralServices.pendingStore.load(), saved.token == record.token else {
                ReferralServices.endRedeem()
                resume(context: context, completion: completion)
                return
            }
            run(
                saved, claim: claim, readMode: readMode, context: context,
                pendingRetried: true, completion: completion
            )
        }
    }

    /// A pending reply is the server saying "not yet", not a failed attempt, so
    /// it gives the attempt back. Only while the record is still this run's own.
    private static func refundAttempt(of record: PendingRedemption) {
        guard ReferralServices.pendingStore.load()?.token == record.token else { return }
        var refunded = record
        refunded.attempts = max(0, record.attempts - 1)
        ReferralServices.pendingStore.save(refunded)
    }

    /// The server used the code, or took a `wl1t_` code as a test: the clipboard
    /// no longer needs it. Empties the clipboard only while it holds what the
    /// code came from.
    private static func clearClipboard(_ claim: TetherClaim, after tether: TetherResponse?) {
        guard claim.isUsed(by: tether) else { return }
        claim.clearIfHeld(on: TetherServices.clipboard)
    }

    private static func finish(
        _ result: Result<RecoveryRedeemOutcome, WarpLinkError>,
        record: PendingRedemption,
        claim: TetherClaim,
        context: Context
    ) -> Finished {
        switch result {
        case let .success(.answered(response)) where response.tether?.isPending == true:
            // Not final: the record stays for the retry, and for the next launch.
            refundAttempt(of: record)
            context.log?.log("Code is pending on the server, will ask again")
            return Finished(outcome: .success(nil), tether: response.tether)
        case let .success(.answered(response)):
            clearPending(ifHolding: record)
            if response.tether?.test == true {
                TetherServices.recordTestReceipt(response.tether?.testReceipt)
                context.log?.log("Test code received, nothing recorded")
                return Finished(outcome: .success(nil), tether: response.tether)
            }
            let applied = apply(response, claim: claim, record: record, context: context)
            return Finished(
                outcome: .success(applied.link), tether: response.tether, settle: applied.settle,
                upgradesRoute: applied.upgradesRoute
            )
        case let .success(.refused(refusal)):
            // The same code would be refused again, so the record ends here.
            clearPending(ifHolding: record)
            context.log?.log("Referral redeem refused: \(refusal.error.localizedDescription)")
            return Finished(outcome: .failure(refusal.error))
        case let .failure(error):
            settleFailure(error, record: record, context: context)
            return Finished(outcome: .failure(error))
        }
    }

    /// The outcome of a run and what it must do once the SDK lock is released.
    private struct Finished {
        let outcome: Result<WarpLinkDeepLink?, WarpLinkError>
        var tether: TetherResponse?
        var settle: () -> Void = {}
        /// The exact link replaced a different one that `onLink` already had.
        var upgradesRoute = false
    }

    /// Any failure but a refusal keeps the record for a later launch, until it
    /// runs out of attempts or time.
    private static func settleFailure(
        _ error: WarpLinkError, record: PendingRedemption, context: Context
    ) {
        let spent = !record.hasAttemptsLeft || record.isExpired(at: ReferralServices.now())
        if spent {
            clearPending(ifHolding: record)
        }
        context.log?.log("Referral redeem failed: \(error.localizedDescription)")
    }

    /// Clears the kept record only while it is still this run's own. A newer
    /// paste may have replaced it during the request.
    private static func clearPending(ifHolding record: PendingRedemption) {
        guard ReferralServices.pendingStore.load()?.token == record.token else { return }
        ReferralServices.pendingStore.clear()
    }

    private static func apply(
        _ response: AttributionResponse,
        claim: TetherClaim,
        record: PendingRedemption,
        context: Context
    ) -> (link: WarpLinkDeepLink?, settle: () -> Void, upgradesRoute: Bool) {
        let evidence = ReferralServices.evidenceStore
        evidence.remember(installId: response.installId)
        guard let matched = ReferralMatch.deepLink(from: response) else {
            context.log?.log("Code redeemed, no link to route to")
            return (nil, {}, false)
        }
        evidence.remember(token: claim.code.recoveryToken ?? record.token, expiresAt: record.expiresAt)
        // The link `onLink` really received, an estimate from the first-launch
        // check or an earlier exact link. A different exact link then reaches
        // `onLink` a second time. The same link does not, whatever its evidence.
        let delivered = context.store.onLinkDeliveredRoute
        let settle = WarpLink.recordRedeemedMatchLocked(matched, store: context.store)
        context.log?.log("Code redeemed: \(matched.linkId)")
        let replaces = context.routesExactToOnLink && delivered != nil && delivered != matched.routeIdentity
        return (matched, settle, replaces)
    }
}
