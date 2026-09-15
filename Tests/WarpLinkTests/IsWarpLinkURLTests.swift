import XCTest
@testable import WarpLink

/// `WarpLink.isWarpLinkURL` answers exactly what `open(_:)` answers.
///
/// `open(_:)` refuses a foreign URL before it touches anything:
/// `guard url.isWarpLinkUniversalLink(domains: knownDomains())` runs before
/// `shouldSuppressDuplicate`. A host that forwards every incoming URL had no
/// way to make the same decision at the same point, so it had to resolve first
/// and read the refusal off a `WarpLinkError.invalidURL`, which arrives after
/// the state a claim changed. This makes the check askable.
///
/// The accept-set is therefore not this function's own: it is
/// `URL.isWarpLinkUniversalLink`'s, over `knownDomains()`. These tests pin that
/// they are the same set rather than two copies of one rule.
final class IsWarpLinkURLTests: XCTestCase {

    override func setUp() {
        super.setUp()
        WarpLink.reset()
    }

    override func tearDown() {
        WarpLink.reset()
        super.tearDown()
    }

    private func url(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid test URL: \(string)")
        }
        return url
    }

    func testDefaultDomainWithASlugIsAWarpLinkURL() {
        XCTAssertTrue(WarpLink.isWarpLinkURL(url("https://aplnk.to/abc123")))
    }

    func testCustomSchemeIsNotAWarpLinkURL() {
        XCTAssertFalse(WarpLink.isWarpLinkURL(url("myapp://oauth/callback")))
    }

    func testUnknownHostIsNotAWarpLinkURL() {
        XCTAssertFalse(WarpLink.isWarpLinkURL(url("https://example.com/abc123")))
    }

    /// The `apple-app-site-association` WarpLink publishes defaults to
    /// `paths: ["*"]`, so iOS hands the app marketing pages too. Claiming those
    /// would swallow URLs the SDK cannot resolve. Same rule as `warpLinkSlug`.
    func testMultiSegmentPathOnAKnownHostIsNotAWarpLinkURL() {
        XCTAssertFalse(WarpLink.isWarpLinkURL(url("https://aplnk.to/blog/hello")))
    }

    func testBareDefaultDomainIsNotAWarpLinkURL() {
        XCTAssertFalse(WarpLink.isWarpLinkURL(url("https://aplnk.to/")))
    }

    func testQueryAndFragmentDoNotChangeTheAnswer() {
        XCTAssertTrue(WarpLink.isWarpLinkURL(url("https://aplnk.to/abc123?utm_source=x")))
        XCTAssertTrue(WarpLink.isWarpLinkURL(url("https://aplnk.to/abc123#section")))
    }

    /// The locally declared half of the set, the one `configure` establishes
    /// synchronously from `WarpLinkOptions.linkDomains` and the Info.plist. Set
    /// here directly rather than through `configure`, which would also start
    /// key validation over the network; that wiring is `WarpLinkLinkDomainsTests`'
    /// subject, and the accept-set is this one's.
    func testDeclaredCustomDomainIsAWarpLinkURL() {
        XCTAssertFalse(WarpLink.isWarpLinkURL(url("https://links.example.com/abc123")))
        WarpLink.localDomains = [WarpLink.defaultDomain, "links.example.com"]
        XCTAssertTrue(WarpLink.isWarpLinkURL(url("https://links.example.com/abc123")))
        XCTAssertTrue(WarpLink.isWarpLinkURL(url("https://aplnk.to/abc123")))
    }

    func testDomainFromServerValidationIsAWarpLinkURL() {
        WarpLink.serverDomains = ["go.example.com"]
        XCTAssertTrue(WarpLink.isWarpLinkURL(url("https://go.example.com/abc123")))
    }

    func testMixedCaseHostStillMatchesItsLowercasedDomain() {
        WarpLink.serverDomains = ["links.example.com"]
        XCTAssertTrue(WarpLink.isWarpLinkURL(url("https://Links.Example.Com/abc123")))
    }

    /// Answering does not depend on `configure`, so a host can ask from the
    /// moment it has a URL. Before `configure` the known set is `aplnk.to`
    /// alone, which is the documented behaviour, not an accident of ordering.
    func testTheDefaultDomainAnswersBeforeConfigure() {
        XCTAssertFalse(WarpLink.isConfigured)
        XCTAssertTrue(WarpLink.isWarpLinkURL(url("https://aplnk.to/abc123")))
        XCTAssertFalse(WarpLink.isWarpLinkURL(url("https://links.example.com/abc123")))
    }

    /// The whole point of exposing it: asking costs nothing and changes
    /// nothing, so a host can ask before every decision. A check that claimed
    /// the dedupe window would be worse than the resolve it replaces.
    func testAskingClaimsNothing() {
        let link = url("https://aplnk.to/abc123")
        XCTAssertTrue(WarpLink.isWarpLinkURL(link))
        XCTAssertTrue(WarpLink.isWarpLinkURL(link))
        XCTAssertFalse(WarpLink.shouldSuppressDuplicate(link))
    }
}
