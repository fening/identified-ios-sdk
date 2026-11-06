import Foundation

/// An array that decodes as empty when its key is missing or its value is
/// `null`. Go serialises a nil slice as `null`, and older backends omit fields
/// newer ones send, so the flow must never fail to decode over an absent list.
@propertyWrapper
package struct DefaultEmpty<Element: Decodable & Equatable & Sendable>: Decodable, Equatable, Sendable {
    package var wrappedValue: [Element]

    package init(wrappedValue: [Element] = []) {
        self.wrappedValue = wrappedValue
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = container.decodeNil() ? [] : try container.decode([Element].self)
    }
}

extension KeyedDecodingContainer {
    package func decode<Element>(_ type: DefaultEmpty<Element>.Type, forKey key: Key) throws -> DefaultEmpty<Element> {
        try decodeIfPresent(type, forKey: key) ?? DefaultEmpty()
    }
}

extension JSONDecoder {
    /// The decoder for every backend response: snake_case keys to camelCase.
    package static var identified: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
