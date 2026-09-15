import XCTest
@testable import WarpLink

final class URLWarpLinkTests: XCTestCase {

    private let domains: Set<String> = ["aplnk.to", "links.example.com"]

    private func url(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid test URL: \(string)")
        }
        return url
    }

    // MARK: - warpLinkSlug

    func testSingleSegmentPathIsTheSlug() {
        XCTAssertEqual(url("https://aplnk.to/abc123").warpLinkSlug, "abc123")
    }

    func testTrailingSlashIsIgnored() {
        XCTAssertEqual(url("https://aplnk.to/abc123/").warpLinkSlug, "abc123")
    }

    func testQueryIsStripped() {
        XCTAssertEqual(url("https://aplnk.to/abc123?utm_source=x").warpLinkSlug, "abc123")
    }

    func testFragmentIsStripped() {
        XCTAssertEqual(url("https://aplnk.to/abc123#section").warpLinkSlug, "abc123")
    }

    func testRootPathHasNoSlug() {
        XCTAssertNil(url("https://aplnk.to/").warpLinkSlug)
    }

    func testBareDomainHasNoSlug() {
        XCTAssertNil(url("https://aplnk.to").warpLinkSlug)
    }

    func testMultiSegmentPathHasNoSlug() {
        // A slug can never contain "/", so /blog/hello is not a WarpLink link.
        // Taking the first segment would resolve an unrelated link named "blog".
        XCTAssertNil(url("https://aplnk.to/blog/hello").warpLinkSlug)
    }

    func testMultiSegmentPathWithTrailingSlashHasNoSlug() {
        XCTAssertNil(url("https://aplnk.to/blog/hello/").warpLinkSlug)
    }

    func testPercentEncodedSlashHasNoSlug() {
        // pathComponents decodes %2F, yielding one component that still carries
        // a "/". The slug is interpolated into the resolve URL, so reject it.
        XCTAssertNil(url("https://aplnk.to/a%2Fb").warpLinkSlug)
    }

    // MARK: - isWarpLinkUniversalLink

    func testKnownHostWithSingleSegmentIsAWarpLink() {
        XCTAssertTrue(url("https://aplnk.to/abc123").isWarpLinkUniversalLink(domains: domains))
    }

    func testKnownCustomDomainWithSingleSegmentIsAWarpLink() {
        XCTAssertTrue(
            url("https://links.example.com/abc123").isWarpLinkUniversalLink(domains: domains)
        )
    }

    func testUnknownHostIsNotAWarpLink() {
        XCTAssertFalse(url("https://example.com/abc123").isWarpLinkUniversalLink(domains: domains))
    }

    func testKnownHostWithMultiSegmentPathIsNotAWarpLink() {
        // The published AASA defaults to paths ["*"], so iOS hands the app every
        // URL on the domain. Without this the SDK would claim links it cannot
        // resolve and they would never reach the host app's own router.
        XCTAssertFalse(
            url("https://aplnk.to/blog/hello").isWarpLinkUniversalLink(domains: domains)
        )
    }

    func testKnownHostRootPathIsNotAWarpLink() {
        XCTAssertFalse(url("https://aplnk.to/").isWarpLinkUniversalLink(domains: domains))
    }

    func testKnownHostBareDomainIsNotAWarpLink() {
        XCTAssertFalse(url("https://aplnk.to").isWarpLinkUniversalLink(domains: domains))
    }

    func testKnownHostWithPercentEncodedSlashIsNotAWarpLink() {
        XCTAssertFalse(url("https://aplnk.to/a%2Fb").isWarpLinkUniversalLink(domains: domains))
    }

    func testEmptyDomainSetMatchesNothing() {
        XCTAssertFalse(url("https://aplnk.to/abc123").isWarpLinkUniversalLink(domains: []))
    }
}
