import XCTest

/// The SDK must never read the pasteboard on its own. The only way text reaches
/// it is the system paste control the person taps.
final class ReferralNoPasteboardTests: XCTestCase {

    // conformance: WL-S47
    func testNoSourceFileReadsThePasteboard() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/WarpLink")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var checked = 0
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            checked += 1
            XCTAssertFalse(text.contains("UIPasteboard"), "\(file.lastPathComponent) reads the pasteboard")
            XCTAssertFalse(text.contains("NSPasteboard"), "\(file.lastPathComponent) reads the pasteboard")
        }
        XCTAssertGreaterThan(checked, 10, "the scan must find the sources")
    }
}
