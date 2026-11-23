import Foundation

#if canImport(UIKit)
import UIKit

/// The one place in the SDK that names the pasteboard.
final class SystemClipboard: TetherClipboard {
    let canRead = true
    var changeCount: Int { UIPasteboard.general.changeCount }
    var hasStrings: Bool { UIPasteboard.general.hasStrings }
    func readString() -> String? { UIPasteboard.general.string }
    func clear() { UIPasteboard.general.items = [] }
}

func makeSystemClipboard() -> TetherClipboard { SystemClipboard() }
#else
func makeSystemClipboard() -> TetherClipboard { NoClipboard() }
#endif
