import Foundation

/// An arbitrary JSON value, used for API responses of unknown shape.
///
/// Booleans and numbers are kept apart: `true` never decodes as `1` and `1` never as `true`.
public enum JSONValue: Sendable, Codable, Equatable {
    /// The JSON `null` literal.
    case null

    /// A JSON boolean.
    case bool(Bool)

    /// A JSON number.
    case number(Double)

    /// A JSON string.
    case string(String)

    /// A JSON array.
    case array([JSONValue])

    /// A JSON object.
    case object([String: JSONValue])

    /// Decodes a value of any JSON type.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` if the data is not JSON.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    /// Encodes the value.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: `EncodingError` if a number is not finite.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            if let integer = Int64(exactly: value) {
                try container.encode(integer)
            } else {
                try container.encode(value)
            }
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    /// Parses JSON data.
    ///
    /// - Parameter data: UTF-8 encoded JSON.
    /// - Returns: The parsed value, or `nil` if the data is not valid JSON.
    public static func parse(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Parses a JSON text.
    ///
    /// - Parameter text: A JSON text.
    /// - Returns: The parsed value, or `nil` if the text is not valid JSON.
    public static func parse(_ text: String) -> JSONValue? {
        parse(Data(text.utf8))
    }

    /// Serializes the value as pretty-printed JSON with sorted keys.
    ///
    /// - Returns: The UTF-8 encoded JSON.
    /// - Throws: `EncodingError` if a number is not finite.
    public func prettyPrintedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// The value as a string, or `nil` for other types.
    public var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    /// The value as a number, or `nil` for other types including booleans.
    public var numberValue: Double? {
        if case .number(let value) = self {
            return value
        }
        return nil
    }

    /// The value as an array, or `nil` for other types.
    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    /// The value as an object, or `nil` for other types.
    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    /// Returns a member of an object.
    ///
    /// - Parameter key: The member name.
    /// - Returns: The member, or `nil` if the value is not an object or has no such member.
    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}
