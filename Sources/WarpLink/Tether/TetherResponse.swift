import Foundation

/// The `tether` object on a match response: what the server did with the code
/// the SDK sent.
struct TetherResponse: Equatable {

    /// `accepted`, `not_found`, `rejected`, `test` or `pending`.
    let status: String

    /// True when the server used the code. Only then is the clipboard cleared.
    let accepted: Bool

    /// True when the code was a test code. A test code records nothing.
    let test: Bool

    /// Proof that a test code reached the server, for the host's test screen.
    let testReceipt: String?

    /// For `pending` only: the seconds the server asks the SDK to wait before it
    /// sends the same request again.
    let retryAfterSeconds: Int?

    /// The code is genuine and its tap record is on the way. Not a final answer.
    var isPending: Bool { status == "pending" }

    /// Nil when `value` is not an object that carries a `status`, so a response
    /// from a server without Tether reads as "no answer".
    init?(json value: Any?) {
        guard let json = value as? [String: Any], let status = json["status"] as? String else {
            return nil
        }
        self.status = status
        accepted = json["accepted"] as? Bool ?? false
        test = json["test"] as? Bool ?? false
        testReceipt = json["test_receipt"] as? String
        retryAfterSeconds = (json["retry_after_seconds"] as? NSNumber).map { $0.intValue }
    }

    init(
        status: String, accepted: Bool, test: Bool = false, testReceipt: String? = nil,
        retryAfterSeconds: Int? = nil
    ) {
        self.status = status
        self.accepted = accepted
        self.test = test
        self.testReceipt = testReceipt
        self.retryAfterSeconds = retryAfterSeconds
    }
}
