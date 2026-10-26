import XCTest
@testable import WarpLink

/// Builds invitations the way the server encodes a recovery token:
/// `tokenId(16) | expiresAt uint32 big endian | version(1) | tag(16)`.
enum ReferralTokenFixture {

    static func token(expiresAt: UInt32, filler: UInt8 = 7) -> String {
        var bytes = [UInt8](repeating: filler, count: 16)
        bytes += [
            UInt8(expiresAt >> 24 & 0xFF), UInt8(expiresAt >> 16 & 0xFF),
            UInt8(expiresAt >> 8 & 0xFF), UInt8(expiresAt & 0xFF),
        ]
        bytes.append(1)
        bytes += [UInt8](repeating: filler &+ 1, count: 16)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

final class ReferralInvitationTests: XCTestCase {

    // conformance: WL-S40
    func testParsesTheTokenTheHandoffPageCopies() throws {
        let token = ReferralTokenFixture.token(expiresAt: 1_900_000_000)

        let invitation = try XCTUnwrap(ReferralInvitation.parse(token))

        XCTAssertEqual(invitation.token, token)
        XCTAssertEqual(invitation.expiresAt, Date(timeIntervalSince1970: 1_900_000_000))
    }

    func testTokenIsFiftyCharacters() {
        XCTAssertEqual(ReferralTokenFixture.token(expiresAt: 1).count, 50)
    }

    func testSurroundingWhitespaceIsIgnoredAndRemovedFromTheToken() throws {
        let token = ReferralTokenFixture.token(expiresAt: 1_900_000_000)

        let invitation = try XCTUnwrap(ReferralInvitation.parse("  \n\(token)\n "))

        XCTAssertEqual(invitation.token, token)
    }

    // conformance: WL-S41
    func testTextThatIsNotAnInvitationIsRefused() {
        let token = ReferralTokenFixture.token(expiresAt: 1_900_000_000)
        let refused = [
            "",
            "hello world",
            "https://aplnk.to/abc123",
            "my password is hunter2",
            String(token.dropLast()),
            token + "A",
            "\(token.dropLast())!",
            "\(token.dropLast()) ",
            "prefix \(token)",
            "\(token) suffix",
            String(repeating: "A", count: 50) + "\n" + String(repeating: "A", count: 50),
        ]

        for text in refused {
            XCTAssertNil(ReferralInvitation.parse(text), "\(text) is not an invitation")
        }
    }

    func testFiftyCharactersThatDecodeToTheWrongLengthAreRefused() {
        // 50 base64url characters always decode to 37 bytes, so a bad length
        // can only come from characters outside the alphabet.
        XCTAssertNil(ReferralInvitation.parse(String(repeating: "=", count: 50)))
        XCTAssertNil(ReferralInvitation.parse(String(repeating: "+", count: 50)))
        XCTAssertNil(ReferralInvitation.parse(String(repeating: "é", count: 50)))
    }

    func testExpiryIsInclusive() throws {
        let invitation = try XCTUnwrap(
            ReferralInvitation.parse(ReferralTokenFixture.token(expiresAt: 1_900_000_000))
        )

        XCTAssertFalse(invitation.isExpired(at: Date(timeIntervalSince1970: 1_899_999_999)))
        XCTAssertTrue(invitation.isExpired(at: Date(timeIntervalSince1970: 1_900_000_000)))
        XCTAssertTrue(invitation.isExpired(at: Date(timeIntervalSince1970: 1_900_000_001)))
    }

    func testTheHighestExpiryDoesNotOverflow() throws {
        let invitation = try XCTUnwrap(
            ReferralInvitation.parse(ReferralTokenFixture.token(expiresAt: UInt32.max))
        )

        XCTAssertEqual(invitation.expiresAt, Date(timeIntervalSince1970: TimeInterval(UInt32.max)))
    }
}
