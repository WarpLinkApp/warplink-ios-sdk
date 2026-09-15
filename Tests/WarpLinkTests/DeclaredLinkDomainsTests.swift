import XCTest
@testable import WarpLink

/// The Info.plist half of the declaration, tested at the parse boundary.
///
/// The value arrives from `Bundle.object(forInfoDictionaryKey:)` as `Any?`, so
/// the parse is where a host's plist mistake either becomes an empty list or a
/// crash at launch. Testing it here needs no app target: only the raw value.
final class DeclaredLinkDomainsTests: XCTestCase {

    func testParsesAnArrayOfStrings() {
        XCTAssertEqual(
            DeclaredLinkDomains.parse(["a.example.com", "b.example.com"]),
            ["a.example.com", "b.example.com"]
        )
    }

    func testParsesOneCommaSeparatedString() {
        // Xcode's plist editor defaults a new row to String, so this is the
        // spelling a developer reaches by accident, and the only one Android's
        // manifest allows.
        XCTAssertEqual(
            DeclaredLinkDomains.parse("a.example.com,b.example.com"),
            ["a.example.com", "b.example.com"]
        )
    }

    func testIgnoresAMissingOrUnusableValue() {
        XCTAssertEqual(DeclaredLinkDomains.parse(nil), [])
        XCTAssertEqual(DeclaredLinkDomains.parse(42), [])
        // A mistyped row drops itself and nothing else. See
        // testOneMistypedRowDoesNotDiscardItsSiblings for why that matters.
        XCTAssertEqual(DeclaredLinkDomains.parse(["a.example.com", 7]), ["a.example.com"])
    }

    func testHostAppWithNoDeclarationIsUnaffected() {
        // Under SwiftPM the main bundle is the test runner, which carries no
        // WarpLinkDomains key: the same state as every existing integration.
        XCTAssertTrue(Bundle.main.declaredLinkDomains().isEmpty)
    }

    func testOneMistypedRowDoesNotDiscardItsSiblings() {
        // Xcode types each plist row on its own, so a developer can leave one
        // as Boolean without noticing. Casting the array whole would then throw
        // away the correct rows too, and the app would show exactly the
        // first-launch failure this option exists to remove.
        let parsed = DeclaredLinkDomains.parse(
            ["links.example.com", true, "links.other.com", 42] as [Any]
        )
        XCTAssertEqual(parsed, ["links.example.com", "links.other.com"])
    }

    func testAnArrayOfNonStringsYieldsNothingRatherThanCrashing() {
        XCTAssertEqual(DeclaredLinkDomains.parse([true, 42] as [Any]), [])
    }
}
