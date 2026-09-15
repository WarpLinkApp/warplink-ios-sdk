import XCTest
@testable import WarpLink

/// The tapped URL's RAW query string reaches the server intact.
///
/// The server reads `params` with `searchParams.get`, which is one transport
/// decode, and then parses the result as a query string. So the SDK must send
/// the raw, percent-encoded query, encoded once for transport. A decoded source
/// splits `both=x%26y` into two parameters and turns the `+` in `a%2Bb%40x.com`
/// into a space, and a double encode leaves literal `%25` sequences behind, so
/// these assert on the bytes the SDK put on the wire and then read them back
/// the way the server does.
final class ResolveParamsTests: XCTestCase {

    private let apiKey = "wl_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
    private var transport: InlineTransport!

    /// A space, a `%`, an `&`, a `+`, an `@` and a nested URL: every character
    /// that breaks under a missed encode, a double encode or a decoded source.
    private static let tapped =
        "https://aplnk.to/abc123?note=a%20b&pct=100%25&both=x%26y"
        + "&email=a%2Bb%40x.com&next=%2Fp%3Fa%3D1%26b%3D2"

    /// The tapped URL's raw query, which is what one transport decode must
    /// return on the server.
    private static let rawQuery =
        "note=a%20b&pct=100%25&both=x%26y&email=a%2Bb%40x.com&next=%2Fp%3Fa%3D1%26b%3D2"

    override func setUp() {
        super.setUp()
        WarpLink.reset()
        transport = InlineTransport.serving { path in
            path.contains("resolve") ? Self.linkJSON : ["valid": true, "domains": ["aplnk.to"]]
        }
        makeSDKSynchronous(transport)
    }

    override func tearDown() {
        WarpLink.reset()
        transport = nil
        super.tearDown()
    }

    func testTappedQueryStringIsEncodedExactlyOnceOnTheWire() throws {
        let query = try sentQuery(forTapping: Self.tapped)

        // Every character outside RFC 3986's unreserved set is escaped once, so
        // the whole raw query arrives as one value of one parameter.
        XCTAssertEqual(
            query,
            "domain=aplnk.to&params=note%3Da%2520b%26pct%3D100%2525%26both%3Dx%2526y"
            + "%26email%3Da%252Bb%2540x.com%26next%3D%252Fp%253Fa%253D1%2526b%253D2"
        )
    }

    func testTappedQueryStringRoundTrips() throws {
        let raw = try rawParamsValue(in: try sentQuery(forTapping: Self.tapped))

        // Decode once, exactly as the server's `searchParams.get` does. What
        // comes back is the raw query, byte for byte.
        let decoded = try XCTUnwrap(raw.removingPercentEncoding)
        XCTAssertEqual(decoded, Self.rawQuery)

        // Then parsed the way `URLSearchParams` parses it, which is what the
        // server hands to the redirect path's parameter shaping.
        let pairs = Self.queryPairs(decoded)
        XCTAssertEqual(pairs["note"], "a b")
        XCTAssertEqual(pairs["pct"], "100%")
        // The whole point of sending raw: an escaped `&` stays inside one
        // value instead of becoming a second, bare parameter.
        XCTAssertEqual(pairs["both"], "x&y")
        // And an escaped `+` stays a `+` instead of being read as a space.
        XCTAssertEqual(pairs["email"], "a+b@x.com")
        XCTAssertEqual(pairs["next"], "/p?a=1&b=2")
        XCTAssertNil(pairs["y"])
    }

    func testTappedURLWithoutAQuerySendsNoParams() throws {
        XCTAssertEqual(try sentQuery(forTapping: "https://aplnk.to/abc123"), "domain=aplnk.to")
    }

    // MARK: - Helpers

    /// Opens `tapped` and returns the resolve request's query, still encoded.
    private func sentQuery(forTapping tapped: String) throws -> String {
        WarpLink.configure(apiKey: apiKey, options: WarpLinkOptions(
            autoDeferredCheck: false,
            onLink: { _ in }
        ))
        XCTAssertTrue(WarpLink.open(try XCTUnwrap(URL(string: tapped))))

        let sent = try XCTUnwrap(transport.requests.last {
            $0.url?.path.contains("/links/resolve/") == true
        })
        return try XCTUnwrap(sent.url?.query)
    }

    /// The `params` value as it sits on the wire, still encoded.
    private func rawParamsValue(in query: String) throws -> String {
        let match = query.split(separator: "&").first { $0.hasPrefix("params=") }
        return String(try XCTUnwrap(match).dropFirst("params=".count))
    }

    /// Splits a query string the way `URLSearchParams` does: on `&`, then once
    /// on `=`, then each half is percent-decoded with a literal `+` read as a
    /// space. A value-only pair becomes an empty value rather than a crash.
    private static func queryPairs(_ query: String) -> [String: String] {
        var pairs: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard let name = parts.first else { continue }
            let value = parts.count > 1 ? String(parts[1]) : ""
            pairs[component(String(name))] = component(value)
        }
        return pairs
    }

    private static func component(_ raw: String) -> String {
        let spaced = raw.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }

    private static let linkJSON: [String: Any] = [
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "slug": "abc123",
        "domain": "aplnk.to",
        "destination_url": "https://example.com",
        "ios_url": "myapp://page",
        "ios_fallback_url": NSNull(),
        "custom_params": ["promo": "summer"],
        "created_at": "2026-01-01T00:00:00.000Z",
    ]
}
