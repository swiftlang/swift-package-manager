/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A type which can be mapped from JSON.
public protocol JSONMappable {
    /// Create an object from given JSON.
    init(json: JSON) throws
}

extension JSON {

    /// Describes an error occurred during JSON mapping.
    public enum MapError: Error {
        /// The key is missing in JSON.
        case missingKey(String)

        /// Got a different type than expected.
        case typeMismatch(key: String, expected: Any.Type, json: JSON)

        /// A custom error. Clients can use this in their mapping method.
        case custom(key: String?, message: String)
    }

    /// Returns a JSON mappable object from a given key.
    public func get<T: JSONMappable>(_ key: String) throws -> T {
        let object: JSON = try get(key)
        return try T(json: object)
    }

    /// Returns an optional JSON mappable object from a given key.
    public func get<T: JSONMappable>(_ key: String) -> T? {
        return try? get(key)
    }

    /// Returns a JSON mappable array from a given key.
    public func get<T: JSONMappable>(_ key: String) throws -> [T] {
        let array: [JSON] = try get(key)
        return try array.map(T.init(json:))
    }

    /// Returns a JSON mappable dictionary from a given key.
    public func get<T: JSONMappable>(_ key: String) throws -> [String: T] {
        let object: JSON = try get(key)
        guard case .dictionary(let value) = object else {
            throw MapError.typeMismatch(
                key: key, expected: Dictionary<String, JSON>.self, json: object)
        }
        return try Dictionary(items: value.map({ ($0.0, try T.init(json: $0.1)) }))
    }

    /// Returns a JSON mappable dictionary from a given key.
    public func get(_ key: String) throws -> [String: JSON] {
        let object: JSON = try get(key)
        guard case .dictionary(let value) = object else {
            throw MapError.typeMismatch(
                key: key, expected: Dictionary<String, JSON>.self, json: object)
        }
        return value
    }

    /// Returns JSON entry in the dictionary from a given key.
    public func get(_ key: String) throws -> JSON {
        guard case .dictionary(let dict) = self else {
            throw MapError.typeMismatch(
                key: key, expected: Dictionary<String, JSON>.self, json: self)
        }
        guard let object = dict[key] else {
            throw MapError.missingKey(key)
        }
        return object
    }

    /// Returns JSON array entry in the dictionary from a given key.
    public func get(_ key: String) throws -> [JSON] {
		let object: JSON = try get(key)
        guard case .array(let array) = object else {
            throw MapError.typeMismatch(key: key, expected: Array<JSON>.self, json: object)
        }
        return array
    }
}

// MARK: - Conformance for basic JSON types.

extension Int: JSONMappable {
    public init(json: JSON) throws {
        guard case .int(let int) = json else {
            throw JSON.MapError.custom(key: nil, message: "expected int, got \(json)")
        }
        self = int
    }
}

extension String: JSONMappable {
    public init(json: JSON) throws {
        guard case .string(let str) = json else {
            throw JSON.MapError.custom(key: nil, message: "expected string, got \(json)")
        }
        self = str
    }
}

extension Bool: JSONMappable {
    public init(json: JSON) throws {
        guard case .bool(let bool) = json else {
            throw JSON.MapError.custom(key: nil, message: "expected bool, got \(json)")
        }
        self = bool
    }
}

extension Double: JSONMappable {
    public init(json: JSON) throws {
        guard case .double(let double) = json else {
            throw JSON.MapError.custom(key: nil, message: "expected double, got \(json)")
        }
        self = double
    }
}
