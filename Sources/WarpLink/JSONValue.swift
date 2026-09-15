import Foundation

/// A JSON value that is both `Codable` and `Sendable`.
///
/// Backs `WarpLinkDeepLink.customParams`, whose contents are arbitrary JSON
/// supplied per link. Replaces `[String: Any]`, which is neither `Codable`
/// (so the deep link could not be persisted or serialized) nor `Sendable`.
///
/// Read values with the typed accessors, e.g.:
/// ```swift
/// let id = deepLink.customParams["product_id"]?.stringValue
/// let n  = deepLink.customParams["count"]?.intValue
/// ```
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
}

// MARK: - Typed accessors

public extension JSONValue {
    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
        case let .int(value): return value
        case let .double(value): return Int(exactly: value.rounded(.towardZero))
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case let .double(value): return value
        case let .int(value): return Double(value)
        default: return nil
        }
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    /// The value lowered to a Foundation/JSON object graph
    /// (`String`/`Int`/`Double`/`Bool`/`[String: Any]`/`[Any]`/`NSNull`).
    /// Used to bridge `customParams` to Objective-C / React Native, since the
    /// `JSONValue` enum itself is not Objective-C representable.
    var foundationValue: Any {
        switch self {
        case let .string(value): return value
        case let .int(value): return value
        case let .double(value): return value
        case let .bool(value): return value
        case let .object(value): return value.mapValues { $0.foundationValue }
        case let .array(value): return value.map { $0.foundationValue }
        case .null: return NSNull()
        }
    }
}

// MARK: - Conversion from Foundation JSON objects

extension JSONValue {
    /// Build a `JSONValue` from a `JSONSerialization` object graph
    /// (`NSNull`, `NSNumber`, `String`, `[String: Any]`, `[Any]`).
    init(any value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            self = JSONValue.fromNumber(number)
        case let string as String:
            self = .string(string)
        case let dict as [String: Any]:
            self = .object(dict.mapValues { JSONValue(any: $0) })
        case let array as [Any]:
            self = .array(array.map { JSONValue(any: $0) })
        default:
            self = .null
        }
    }

    private static func fromNumber(_ number: NSNumber) -> JSONValue {
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
        if CFNumberIsFloatType(number) { return .double(number.doubleValue) }
        return .int(number.intValue)
    }
}

// MARK: - Codable

public extension JSONValue {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
