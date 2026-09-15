import XCTest
@testable import WarpLink

/// GOLDEN VECTORS. This exact table is asserted by the iOS SDK and by the Android
/// SDK, row for row. A developer declares the same domain in both apps, from the
/// same dashboard, usually by pasting the same string, so the two platforms have to
/// reduce it identically. A divergence has to fail a test rather than surface as
/// "the link works on Android but not on iOS".
///
/// The table is duplicated per platform on purpose: there is no build step that
/// could share it across two package managers. The first version of these two
/// normalizers drifted on five inputs while BOTH files claimed the other asserted
/// the same table, and the two tables did not share a single row. Keep them
/// identical. Change a rule, change both, add the row to both.
private let GOLDEN: [(String, String?)] = [
    // Already a bare host: unchanged.
    ("links.example.com", "links.example.com"),
    ("aplnk.to", "aplnk.to"),
    // Whitespace, from a copied cell or a wrapped manifest value.
    ("  links.example.com  ", "links.example.com"),
    ("\tlinks.example.com\n", "links.example.com"),
    // Hosts are case insensitive, so a declaration is folded down.
    ("LINKS.EXAMPLE.COM", "links.example.com"),
    ("Links.Example.Com", "links.example.com"),
    // A pasted URL is reduced to its host.
    ("https://links.example.com", "links.example.com"),
    ("https://links.example.com/", "links.example.com"),
    ("http://links.example.com/a/b", "links.example.com"),
    ("HTTPS://Links.Example.Com/", "links.example.com"),
    ("https://links.example.com/abc123?utm_source=x#frag", "links.example.com"),
    ("https://links.example.com?a=b", "links.example.com"),
    ("links.example.com/abc123", "links.example.com"),
    ("links.example.com#frag", "links.example.com"),
    // A protocol relative href, which is what a copied <a> tag often gives.
    ("//links.example.com", "links.example.com"),
    ("//links.example.com/abc", "links.example.com"),
    // Credentials are dropped. Without this the host becomes `user`.
    ("user@links.example.com", "links.example.com"),
    ("https://user:pw@links.example.com/", "links.example.com"),
    // A port is dropped: the host a link arrives with never carries one.
    ("https://links.example.com:8443/", "links.example.com"),
    ("links.example.com:8443", "links.example.com"),
    // Only a real port. A non numeric suffix is left alone rather than truncated,
    // and an IPv6 literal keeps its colons.
    ("links.example.com:notaport", "links.example.com:notaport"),
    ("[::1]:8443", "[::1]"),
    // `www.` is a real and different host, so it survives.
    ("www.example.com", "www.example.com"),
    ("https://www.example.com/", "www.example.com"),
    // Nothing that names a host.
    ("", nil),
    ("   ", nil),
    ("https://", nil),
    ("/", nil),
    ("/abc123", nil),
    ("//", nil),
    // Invisible characters a paste can carry: stripped identically on both
    // platforms, from an explicit list, because the platform trims disagree.
    ("\u{200B}links.example.com", "links.example.com"),
    ("links.example.com\u{200B}", "links.example.com"),
    ("\u{00A0}links.example.com\u{00A0}", "links.example.com"),
    ("\u{FEFF}links.example.com", "links.example.com"),
    ("\u{2060}links.example.com", "links.example.com"),
    ("links.example.com\u{200D}", "links.example.com"),
    // A control character is not in the list, on either side, so it stays.
    ("\u{1F}links.example.com", "\u{1F}links.example.com"),
]

final class LinkDomainNormalizerTests: XCTestCase {

    func testGoldenVectors() {
        for (input, expected) in GOLDEN {
            XCTAssertEqual(
                LinkDomainNormalizer.normalize(input), expected,
                "normalize(\(input.debugDescription))"
            )
        }
    }

    func testNormalizeAllDropsEntriesWithNoHost() {
        let result = LinkDomainNormalizer.normalizeAll(["links.example.com", "", "   ", "https://"])
        XCTAssertEqual(result, ["links.example.com"])
    }

    func testNormalizeAllCollapsesSpellingsOfTheSameHost() {
        // A developer who declares the domain in code AND in the Info.plist,
        // spelled differently, must end up with one host, not two.
        let result = LinkDomainNormalizer.normalizeAll([
            "https://Links.Example.Com/", "links.example.com", "  LINKS.EXAMPLE.COM  ",
        ])
        XCTAssertEqual(result, ["links.example.com"])
    }

    func testNormalizeAllKeepsDistinctHosts() {
        let result = LinkDomainNormalizer.normalizeAll(["a.example.com", "https://b.example.com"])
        XCTAssertEqual(result, ["a.example.com", "b.example.com"])
    }

    func testNormalizedDomainMatchesTheHostOfAMixedCaseLink() {
        // The whole point of the normalizer: its output is compared against the
        // host of an incoming link, and Foundation preserves the case it was
        // handed (`URL.host` here is literally "Links.Example.Com"). Both sides
        // fold, or a developer's own domain is rejected over capitals.
        let url = URL(string: "https://Links.Example.Com/abc123")!
        let declared = LinkDomainNormalizer.normalizeAll(["https://links.example.com/"])

        XCTAssertEqual(url.warpLinkHost, "links.example.com")
        XCTAssertTrue(url.isWarpLinkUniversalLink(domains: declared))
    }
}
