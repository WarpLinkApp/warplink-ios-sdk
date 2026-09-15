import XCTest
@testable import WarpLink

final class FingerprintCollectorTests: XCTestCase {

    private var collector: FingerprintCollector!

    override func setUp() {
        super.setUp()
        collector = FingerprintCollector()
    }

    func testCollectReturnsRawPreferredLanguage() {
        let signals = collector.collect()
        XCTAssertEqual(signals.acceptLanguage, Locale.preferredLanguages.first ?? "")
    }

    func testAcceptLanguageIsSingleRawValueNotJoinedList() {
        // Contract: send the raw first preferred language, not a comma-joined
        // list. The server normalizes.
        let signals = collector.collect()
        XCTAssertFalse(
            signals.acceptLanguage.contains(","),
            "SDK must send a single raw preferred language, not a joined list"
        )
    }

    func testTimezoneOffsetIsValidInteger() {
        let signals = collector.collect()
        // Valid timezone offsets range from -720 to +840 minutes.
        XCTAssertGreaterThanOrEqual(signals.timezoneOffset, -720)
        XCTAssertLessThanOrEqual(signals.timezoneOffset, 840)
    }

    func testTimezoneOffsetUsesJSConvention() {
        // JS getTimezoneOffset() convention: sign-inverted minutes.
        let signals = collector.collect()
        XCTAssertEqual(signals.timezoneOffset, -(TimeZone.current.secondsFromGMT() / 60))
    }

    func testDeterminism() {
        let first = collector.collect()
        let second = collector.collect()
        XCTAssertEqual(first.acceptLanguage, second.acceptLanguage)
        XCTAssertEqual(first.timezoneOffset, second.timezoneOffset)
    }

    func testIdfvPropertyType() {
        // idfv returns String? — on the macOS test host it may be nil, but the
        // property must exist and return the correct type. If non-nil it should
        // be a valid UUID.
        let idfv: String? = collector.idfv
        if let value = idfv {
            XCTAssertFalse(value.isEmpty)
            XCTAssertNotNil(UUID(uuidString: value), "IDFV should be a valid UUID")
        }
    }

    func testCollectsIANAZoneName() {
        let signals = FingerprintCollector().collect()

        // The server prefers the zone name: far more entropy than the offset,
        // and it does not shift at a daylight-saving boundary.
        XCTAssertFalse(signals.timezone.isEmpty)
        XCTAssertEqual(signals.timezone, TimeZone.current.identifier)
        // Ask Foundation whether it is a zone, rather than guessing from the
        // shape of the string. The old test required a "/" or the exact word
        // UTC, which is a claim about how the MACHINE is configured and not
        // about the SDK: a GitHub macOS runner reports `GMT`, a real tzdb zone
        // that the shape test rejected. `knownTimeZoneIdentifiers` is not the
        // predicate either, because it contains GMT but NOT UTC.
        XCTAssertNotNil(
            TimeZone(identifier: signals.timezone),
            "expected an identifier Foundation recognises as a zone, got \(signals.timezone)"
        )
    }

    func testTimezoneOffsetSignIsTheJSConventionForANamedZone() {
        // Two zones with no daylight saving, so the value is stable all year.
        let kolkata = FingerprintCollector(timeZone: TimeZone(identifier: "Asia/Kolkata")!).collect()
        XCTAssertEqual(kolkata.timezoneOffset, -330, "UTC+5:30 is -330 in the JS convention")
        XCTAssertEqual(kolkata.timezone, "Asia/Kolkata")

        let saoPaulo = FingerprintCollector(timeZone: TimeZone(identifier: "America/Sao_Paulo")!).collect()
        XCTAssertEqual(saoPaulo.timezoneOffset, 180, "UTC-3 is +180 in the JS convention")
    }
}
