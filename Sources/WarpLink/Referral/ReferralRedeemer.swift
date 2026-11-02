import Foundation

/// Redeeming a pasted invitation, and finishing one a network failure left.
///
/// The invitation arrives only through an explicit paste. This type never
/// reads the pasteboard: the text is handed in by the caller.
enum ReferralRedeemer {

    typealias Completion = (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void

    /// The dependencies of one run, gathered once under the SDK lock.
    struct Context {
        let client: APIClient
        let store: Storage
        let deviceId: String?
        let log: Logger?
    }

    /// Redeems `text` when it holds a WarpLink invitation.
    ///
    /// Text that is not an invitation answers `.success(nil)` without a
    /// request: the caller decides how to tell the user. An expired invitation
    /// answers an error without a request. Both leave onboarding free to go on.
    static func redeem(text: String, context: Context, completion: @escaping Completion) {
        guard let invitation = ReferralInvitation.parse(text) else {
            context.log?.log("Pasted text is not a WarpLink invitation, nothing sent")
            completion(.success(nil))
            return
        }
        if invitation.isExpired(at: ReferralServices.now()) {
            completion(.failure(ReferralMessages.Refusal.expired.error))
            return
        }
        // A newer paste replaces an older record, and starts its own count.
        let record = PendingRedemption(token: invitation.token, expiresAt: invitation.expiresAt)
        guard ReferralServices.beginRedeem() else {
            // Kept for the next launch: the run in flight must not be the last
            // word on an invitation the user has since replaced.
            ReferralServices.pendingStore.save(record)
            context.log?.log("A referral redeem is already running, kept this invitation for later")
            completion(.success(nil))
            return
        }
        run(record, context: context, completion: completion)
    }

    /// Finishes the invitation an earlier run could not deliver, if one is
    /// held and still worth sending. Answers nothing when there is none.
    static func resume(context: Context, completion: @escaping Completion) {
        guard let record = ReferralServices.pendingStore.load() else { return }
        guard !record.isExpired(at: ReferralServices.now()), record.hasAttemptsLeft else {
            ReferralServices.pendingStore.clear()
            return
        }
        guard ReferralServices.beginRedeem() else { return }
        run(record, context: context, completion: completion)
    }

    // MARK: - Private

    private static func run(
        _ held: PendingRedemption, context: Context, completion: @escaping Completion
    ) {
        var record = held
        record.attempts += 1
        // Written before the send, so a crash or a kill mid-request still
        // counts the attempt and the token survives for the next launch.
        ReferralServices.pendingStore.save(record)
        let isReinstall = context.store.isReinstall
        let epoch = ReferralServices.epoch
        ReferralBoundedCall.run(
            client: context.client,
            send: { timeout, answer in
                context.client.redeemRecoveryToken(
                    record.token, deviceId: context.deviceId, sdkVersion: WarpLink.sdkVersion,
                    isReinstall: isReinstall, timeout: timeout, completion: answer
                )
            },
            completion: { result in
                finishRun(result, record: record, epoch: epoch, context: context, completion: completion)
            }
        )
    }

    /// Checks the epoch and applies the answer in one hold of the SDK lock, so a
    /// key change or `clearAttribution()` cannot land between the two. An answer
    /// that belongs to state that is gone applies nothing.
    private static func finishRun(
        _ result: Result<RecoveryRedeemOutcome, WarpLinkError>,
        record: PendingRedemption,
        epoch: Int,
        context: Context,
        completion: Completion
    ) {
        WarpLink.lock.lock()
        guard ReferralServices.epoch == epoch else {
            WarpLink.lock.unlock()
            ReferralServices.endRedeem()
            completion(.success(nil))
            return
        }
        let finished = finish(result, record: record, context: context)
        WarpLink.lock.unlock()
        finished.settle()
        ReferralServices.endRedeem()
        completion(finished.outcome)
    }

    private static func finish(
        _ result: Result<RecoveryRedeemOutcome, WarpLinkError>,
        record: PendingRedemption,
        context: Context
    ) -> Finished {
        switch result {
        case let .success(.answered(response)):
            clearPending(ifHolding: record)
            let applied = apply(response, record: record, context: context)
            return Finished(outcome: .success(applied.link), settle: applied.settle)
        case let .success(.refused(refusal)):
            // The same token would be refused again, so the record ends here.
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
        var settle: () -> Void = {}
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
        _ response: AttributionResponse, record: PendingRedemption, context: Context
    ) -> (link: WarpLinkDeepLink?, settle: () -> Void) {
        let evidence = ReferralServices.evidenceStore
        evidence.remember(installId: response.installId)
        guard let matched = ReferralMatch.deepLink(from: response) else {
            context.log?.log("Invitation redeemed, no link to route to")
            return (nil, {})
        }
        evidence.remember(token: record.token, expiresAt: record.expiresAt)
        let settle = WarpLink.recordRedeemedMatchLocked(matched, store: context.store)
        context.log?.log("Invitation redeemed: \(matched.linkId)")
        return (matched, settle)
    }
}
