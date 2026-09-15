import XCTest
@testable import WarpLink

final class JSONValueTests: XCTestCase {

    func testAccessorsReturnTypedValues() {
        XCTAssertEqual(JSONValue.string("hi").stringValue, "hi")
        XCTAssertEqual(JSONValue.int(42).intValue, 42)
        XCTAssertEqual(JSONValue.double(1.5).doubleValue, 1.5)
        XCTAssertEqual(JSONValue.bool(true).boolValue, true)
        XCTAssertEqual(JSONValue.int(7).doubleValue, 7.0)
        XCTAssertNil(JSONValue.string("x").intValue)
        XCTAssertNil(JSONValue.null.stringValue)
    }

    func testInitFromFoundationJSON() {
        let dict: [String: Any] = [
            "s": "text",
            "n": 3,
            "d": 2.5,
            "b": true,
            "nested": ["k": "v"],
            "list": [1, 2],
            "empty": NSNull(),
        ]
        let value = JSONValue(any: dict)
        guard case let .object(object) = value else {
            return XCTFail("Expected object")
        }
        XCTAssertEqual(object["s"]?.stringValue, "text")
        XCTAssertEqual(object["n"]?.intValue, 3)
        XCTAssertEqual(object["d"]?.doubleValue, 2.5)
        XCTAssertEqual(object["b"]?.boolValue, true)
        XCTAssertEqual(object["nested"]?.objectValue?["k"]?.stringValue, "v")
        XCTAssertEqual(object["list"]?.arrayValue?.count, 2)
        XCTAssertEqual(object["empty"], JSONValue.null)
    }

    func testBoolIsNotDecodedAsInt() {
        // NSNumber(true) must map to .bool, not .int(1).
        let value = JSONValue(any: true)
        XCTAssertEqual(value, JSONValue.bool(true))
        XCTAssertNil(value.intValue)
    }

    func testCodableRoundTrip() throws {
        let original: [String: JSONValue] = [
            "str": .string("hello"),
            "int": .int(10),
            "double": .double(3.14),
            "bool": .bool(false),
            "arr": .array([.int(1), .string("two")]),
            "obj": .object(["nested": .bool(true)]),
            "nul": .null,
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([String: JSONValue].self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDeepLinkCodableRoundTrip() throws {
        let link = WarpLinkDeepLink(
            linkId: "l-1",
            destination: "https://example.com",
            deepLinkUrl: "myapp://x",
            customParams: ["promo": .string("summer"), "count": .int(3)],
            isDeferred: true,
            matchType: .probabilistic,
            matchConfidence: 0.7
        )
        let data = try JSONEncoder().encode(link)
        let decoded = try JSONDecoder().decode(WarpLinkDeepLink.self, from: data)
        XCTAssertEqual(decoded, link)
    }

    func testFoundationValueLowersToBridgeablePrimitives() {
        let value = JSONValue.object([
            "s": .string("hi"),
            "n": .int(5),
            "d": .double(1.5),
            "b": .bool(true),
            "arr": .array([.int(1), .string("x")]),
            "nested": .object(["k": .string("v")]),
            "null": .null,
        ])
        let foundation = value.foundationValue as? [String: Any]
        XCTAssertNotNil(foundation)
        XCTAssertEqual(foundation?["s"] as? String, "hi")
        XCTAssertEqual(foundation?["n"] as? Int, 5)
        XCTAssertEqual(foundation?["d"] as? Double, 1.5)
        XCTAssertEqual(foundation?["b"] as? Bool, true)
        XCTAssertEqual((foundation?["arr"] as? [Any])?.count, 2)
        XCTAssertEqual((foundation?["nested"] as? [String: Any])?["k"] as? String, "v")
        XCTAssertTrue(foundation?["null"] is NSNull)
        // The result must be JSON-serializable (i.e. no Swift-enum boxes leak).
        XCTAssertTrue(JSONSerialization.isValidJSONObject(foundation as Any))
    }

    func testIntValueHandlesNonFiniteAndOutOfRangeDoubles() {
        // In-range doubles still truncate toward zero (prior behavior preserved).
        XCTAssertEqual(JSONValue.double(3.7).intValue, 3)
        XCTAssertEqual(JSONValue.double(-3.7).intValue, -3)
        // Non-finite / out-of-range doubles reach `intValue` from untrusted
        // custom_params; `Int(Double)` would trap on all of these, so they must
        // return nil instead of crashing the host app.
        XCTAssertNil(JSONValue.double(.infinity).intValue)
        XCTAssertNil(JSONValue.double(-.infinity).intValue)
        XCTAssertNil(JSONValue.double(.nan).intValue)
        XCTAssertNil(JSONValue.double(1e300).intValue)
    }
}
