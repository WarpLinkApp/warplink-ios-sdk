import Foundation

/// A code taken from the clipboard, and the clipboard state it was taken from.
struct TetherClaim {

    let code: TetherCode

    /// `changeCount` when the code was read or pasted. Nil for a code that did
    /// not come from the clipboard, such as a resumed one.
    let changeCount: Int?

    /// Whether `tether` says the server used this code: a live code only when
    /// it was accepted, a test code only when the server took it as a test.
    func isUsed(by tether: TetherResponse?) -> Bool {
        guard let tether = tether else { return false }
        return code.isTest ? tether.test : tether.accepted
    }

    /// Empties the clipboard only while it is still the state this code came
    /// from. A person who has copied something else since keeps it.
    func clearIfHeld(on clipboard: TetherClipboard) {
        guard let stamp = changeCount, clipboard.canRead, clipboard.changeCount == stamp else { return }
        clipboard.clear()
    }
}
