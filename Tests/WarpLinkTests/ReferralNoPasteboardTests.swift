import XCTest

/// The SDK never reads the pasteboard on its own in the default mode. The
/// pasteboard is named in one file, and the paste components are UIKit only.
final class ReferralNoPasteboardTests: XCTestCase {

    private static let clipboardFile = "SystemClipboard.swift"
    private static let guardLine = "canImport(UIKit)"
    private static let clipboardNames = ["UIPasteboard", "NSPasteboard"]
    private static let pasteControlNames = ["PasteButton(", "UIPasteControl("]

    private func sourceFiles() throws -> [(name: String, text: String)] {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/WarpLink")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var found: [(String, String)] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            found.append((file.lastPathComponent, try String(contentsOf: file, encoding: .utf8)))
        }
        XCTAssertGreaterThan(found.count, 10, "the scan must find the sources")
        return found
    }

    // conformance: WL-S47
    // conformance: WL-S61
    func testOnlyTheGuardedClipboardFileNamesThePasteboard() throws {
        for (name, text) in try sourceFiles() {
            let names = Self.clipboardNames.contains { text.contains($0) }
            if name == Self.clipboardFile {
                XCTAssertTrue(names, "the clipboard file must hold the pasteboard calls")
                XCTAssertTrue(
                    text.hasPrefix("import Foundation\n\n#if \(Self.guardLine)"),
                    "\(name) must open with the UIKit guard"
                )
            } else {
                XCTAssertFalse(names, "\(name) names the pasteboard")
            }
        }
    }

    // conformance: WL-S47
    func testEveryPasteComponentIsGuardedByUIKit() throws {
        var guarded = 0
        for (name, text) in try sourceFiles() where Self.pasteControlNames.contains(where: text.contains) {
            guarded += 1
            XCTAssertTrue(
                text.hasPrefix("#if canImport("),
                "\(name) must start with a canImport guard"
            )
        }
        XCTAssertEqual(guarded, 3, "the SwiftUI button, its UIKit wrapper and the UIKit button")
    }
}
