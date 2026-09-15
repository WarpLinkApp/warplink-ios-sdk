import XCTest
@testable import WarpLink

/// The constant is typed by hand and nothing derives it from the release tag,
/// which is how two published tags came to report the same version over the
/// wire. The CHANGELOG's top entry is the release being cut, so the two must
/// agree on every pull request, not only at the tag.
final class SdkVersionTests: XCTestCase {

    func testSdkVersionMatchesTheTopChangelogEntry() throws {
        let changelog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WarpLinkTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("CHANGELOG.md")
        let text = try String(contentsOf: changelog, encoding: .utf8)

        let regex = try NSRegularExpression(
            pattern: #"^## \[(\d+\.\d+\.\d+)\]"#,
            options: [.anchorsMatchLines]
        )
        let whole = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: whole),
              let versionRange = Range(match.range(at: 1), in: text) else {
            return XCTFail("CHANGELOG.md has no '## [x.y.z]' heading")
        }

        XCTAssertEqual(
            String(text[versionRange]),
            WarpLink.sdkVersion,
            "Sources/WarpLink/WarpLink.swift sdkVersion and the top CHANGELOG entry disagree"
        )
    }
}
