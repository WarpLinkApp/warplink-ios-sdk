import Foundation

/// Redeeming a Tether code or invitation, and finishing one a network failure
/// left.
///
/// The text arrives only from a paste control, an automatic read or a
/// `readTether` call. This type never reads the pasteboard: the text, or the
/// claim made from it, is handed in by the caller.
enum ReferralRedeemer {

    /// What a run learned besides the link.
    struct Detail {
        /// What the server said about the code, when it said anything.
        var tether: TetherResponse?
        /// Why the text was not a code, when nothing was sent.
        var miss: TetherMissReason?
        /// True when the run already sent the exact link to `onLink`, because it
        /// replaced a link `onLink` had been given before. The caller must not
        /// route the same link again.
        var routedToOnLink = false
        /// The store's clear generation, read in the same lock hold as the link.
        /// A caller that sends the link to `onLink` passes it to the dispatch.
        var clearGeneration: Int?
    }

    /// The answer, and the detail that `readTether` and the paste buttons report.
    typealias Report = (Result<WarpLinkDeepLink?, WarpLinkError>, Detail) -> Void

    /// The dependencies of one run, gathered once under the SDK lock.
    struct Context {
        let client: APIClient
        let store: Storage
        let deviceId: String?
        let log: Logger?
        let installationId: String
        let readMode: TetherReadMode
        /// True for a Tether read (paste button, `readTether`): an exact link
        /// that replaces the one `onLink` was given is sent to `onLink` too.
        var routesExactToOnLink = true
    }

    /// Redeems `text` that a paste control handed over, when it holds a code.
    ///
    /// Missing text, or text that is not a code, answers `.success(nil)` without a request and
    /// leaves a miss for the next request to report. `stamp` is the clipboard's
    /// `changeCount` at the paste, so a later clear can tell the clipboard has
    /// not changed. An unprefixed invitation is taken only when
    /// `acceptingInvitation` is true.
    static func redeem(
        text: String?, stamp: Int?, acceptingInvitation: Bool, context: Context,
        completion: @escaping Report
    ) {
        switch TetherReader.reading(of: text, stamp: stamp, acceptingInvitation: acceptingInvitation) {
        case let .miss(reason):
            context.log?.log("Pasted text is not a WarpLink code, nothing sent")
            TetherServices.recordMiss(reason, mode: .pasteButton)
            completion(.success(nil), Detail(miss: reason))
        case let .code(claim):
            redeem(claim: claim, readMode: .pasteButton, context: context, completion: completion)
        }
    }

    /// Redeems a code already taken from the clipboard. An expired code answers
    /// an error without a request. Both leave onboarding free to go on.
    static func redeem(
        claim: TetherClaim, readMode: TetherReadMode, context: Context, completion: @escaping Report
    ) {
        let now = ReferralServices.now()
        let expiresAt = claim.code.expiresAt(now: now)
        if expiresAt <= now {
            completion(.failure(ReferralMessages.Refusal.expired.error), Detail())
            return
        }
        // A newer paste replaces an older record, and starts its own count.
        let record = PendingRedemption(token: claim.code.wireText, expiresAt: expiresAt)
        guard ReferralServices.beginRedeem() else {
            // Kept for the next launch: the run in flight must not be the last
            // word on a code the user has since replaced. A test code is never
            // kept, it records nothing.
            if !claim.code.isTest { ReferralServices.pendingStore.save(record) }
            context.log?.log("A referral redeem is already running, kept this code for later")
            completion(.success(nil), Detail())
            return
        }
        run(record, claim: claim, readMode: readMode, context: context, completion: completion)
    }

    /// Finishes the code an earlier run could not deliver, if one is held and
    /// still worth sending. Answers nothing when there is none.
    static func resume(context: Context, completion: @escaping Report) {
        guard let record = ReferralServices.pendingStore.load() else { return }
        guard !record.isExpired(at: ReferralServices.now()), record.hasAttemptsLeft else {
            ReferralServices.pendingStore.clear()
            return
        }
        guard ReferralServices.beginRedeem() else { return }
        // Nothing to clear: this code is not on the clipboard any more.
        let claim = TetherClaim(
            code: TetherCode.parse(record.token) ?? .invitation(record.token), changeCount: nil
        )
        run(record, claim: claim, readMode: context.readMode, context: context, completion: completion)
    }

    // MARK: - Private

    static func run(
        _ held: PendingRedemption,
        claim: TetherClaim,
        readMode: TetherReadMode,
        context: Context,
        pendingRetried: Bool = false,
        completion: @escaping Report
    ) {
        var record = held
        record.attempts += 1
        // Written before the send, so a crash or a kill mid-request still
        // counts the attempt and the code survives for the next launch.
        if !claim.code.isTest { ReferralServices.pendingStore.save(record) }
        let isReinstall = context.store.isReinstall
        let epoch = ReferralServices.epoch
        let fields = TetherRequestFields(
            installationId: context.installationId, claim: claim, readMode: readMode
        )
        ReferralBoundedCall.run(
            client: context.client,
            send: { timeout, answer in
                context.client.redeemRecoveryToken(
                    tether: fields, deviceId: context.deviceId, sdkVersion: WarpLink.sdkVersion,
                    isReinstall: isReinstall, timeout: timeout, completion: answer
                )
            },
            completion: { result in
                finishRun(
                    result, record: record, claim: claim, epoch: epoch,
                    readMode: readMode, pendingRetried: pendingRetried,
                    context: context, completion: completion
                )
            }
        )
    }
}
