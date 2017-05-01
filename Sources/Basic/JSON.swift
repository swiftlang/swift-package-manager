/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -------------------------------------------------------------------------

 This file defines JSON support infrastructure. It is not designed to be general
 purpose JSON utilities, but rather just the infrastructure which SwiftPM needs
 to manage serialization of data through JSON.
*/

// MARK: JSON Item Definition

/// A JSON value.
///
/// This type uses container wrappers in order to allow for mutable elements.
public enum JSON {
    /// The null value.
    case null

    /// A boolean value.
    case bool(Bool)

    /// An integer value.
    ///
    /// While not strictly present in JSON, we use this as a convenience to
    /// parsing code.
    case int(Int)

    /// A floating-point value.
    case double(Double)

    /// A string.
    case string(String)

    /// An array.
    case array([JSON])

    /// A dictionary.
    case dictionary([String: JSON])
}

/// A JSON representation of an element.
public protocol JSONSerializable {

    /// Return a JSON representation.
    func toJSON() -> JSON
}

extension JSON: CustomStringConvertible {
    public var description: Swift.String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value.description
        case .int(let value): return value.description
        case .double(let value): return value.description
        case .string(let value): return value.debugDescription
        case .array(let values): return values.description
        case .dictionary(let values): return values.description
        }
    }
}

/// Equatable conformance.
extension JSON: Equatable {
    public static func == (lhs: JSON, rhs: JSON) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case (.null, _): return false
        case (.bool(let a), .bool(let b)): return a == b
        case (.bool, _): return false
        case (.int(let a), .int(let b)): return a == b
        case (.int, _): return false
        case (.double(let a), .double(let b)): return a == b
        case (.double, _): return false
        case (.string(let a), .string(let b)): return a == b
        case (.string, _): return false
        case (.array(let a), .array(let b)): return a == b
        case (.array, _): return false
        case (.dictionary(let a), .dictionary(let b)): return a == b
        case (.dictionary, _): return false
        }
    }
}

// MARK: JSON Encoding

extension JSON {
    /// Encode a JSON item into a string of bytes.
    public func toBytes(prettyPrint: Bool = false) -> ByteString {
        let stream = BufferedOutputByteStream()
        write(to: stream, indent: prettyPrint ? 0 : nil)
        if prettyPrint {
            stream.write("\n")
        }
        return stream.bytes
    }

    /// Encode a JSON item into a JSON string
    public func toString(prettyPrint: Bool = false) -> String {
        guard let contents = self.toBytes(prettyPrint: prettyPrint).asString else {
            fatalError("Failed to serialize JSON: \(self)")
        }
        return contents
    }
}

/// Support writing to a byte stream.
extension JSON: ByteStreamable {
    public func write(to stream: OutputByteStream) {
        write(to: stream, indent: nil)
    }

    public func write(to stream: OutputByteStream, indent: Int?) {
        func indentStreamable(offset: Int? = nil) -> ByteStreamable {
            return Format.asRepeating(string: " ", count: indent.flatMap({ $0 + (offset ?? 0) }) ?? 0)
        }
        let shouldIndent = indent != nil
        switch self {
        case .null:
            stream <<< "null"
        case .bool(let value):
            stream <<< Format.asJSON(value)
        case .int(let value):
            stream <<< Format.asJSON(value)
        case .double(let value):
            // FIXME: What happens for NaN, etc.?
            stream <<< Format.asJSON(value)
        case .string(let value):
            stream <<< Format.asJSON(value)
        case .array(let contents):
            stream <<< "[" <<< (shouldIndent ? "\n" : "")
            for (i, item) in contents.enumerated() {
                if i != 0 { stream <<< "," <<< (shouldIndent ? "\n" : " ") }
                stream <<< indentStreamable(offset: 2)
                item.write(to: stream, indent: indent.flatMap({ $0 + 2 }))
            }
            stream <<< (shouldIndent ? "\n" : "") <<< indentStreamable() <<< "]"
        case .dictionary(let contents):
            // We always output in a deterministic order.
            stream <<< "{" <<< (shouldIndent ? "\n" : "")
            for (i, key) in contents.keys.sorted().enumerated() {
                if i != 0 { stream <<< "," <<< (shouldIndent ? "\n" : " ") }
                stream <<<  indentStreamable(offset: 2) <<< Format.asJSON(key) <<< ": "
                contents[key]!.write(to: stream, indent: indent.flatMap({ $0 + 2 }))
            }
            stream <<< (shouldIndent ? "\n" : "") <<< indentStreamable() <<< "}"
        }
    }
}

// MARK: JSON Decoding

import Foundation

enum JSONDecodingError: Swift.Error {
    /// The input byte string is malformed.
    case malformed
}

// NOTE: This implementation is carefully crafted to work correctly on both
// Linux and OS X while still compiling for both. Thus, the implementation takes
// Any even though it could take AnyObject on OS X, and it uses converts to
// direct Swift types (for Linux) even though those don't apply on OS X.
//
// This allows the code to be portable, and expose a portable API, but it is not
// very efficient.

private let nsBooleanType = type(of: NSNumber(value: false))
extension JSON {
    private static func convertToJSON(_ object: Any) -> JSON {
        switch object {
        case is NSNull:
            return .null
        case let value as String:
            return .string(value)

        case let value as NSNumber:
            // Check if this is a boolean.
            //
            // FIXME: This is all rather unfortunate and expensive.
            if type(of: value) === nsBooleanType {
                return .bool(value != 0)
            }

            // Check if this is an exact integer.
            //
            // FIXME: This is highly questionable. Aside from the performance of
            // decoding in this fashion, it means clients which truly have
            // arrays of real numbers will need to be prepared to see either an
            // .int or a .double. However, for our specific use case we usually
            // want to get integers out of JSON, and so it seems an ok tradeoff
            // versus forcing all clients to cast out of a double.
            let asInt = value.intValue
            if NSNumber(value: asInt) == value {
                return .int(asInt)
            }

            // Otherwise, we have a floating point number.
            return .double(value.doubleValue)
        case let value as NSArray:
            return .array(value.map(convertToJSON))
        case let value as NSDictionary:
            var result = [String: JSON]()
            for (key, val) in value {
                result[key as! String] = convertToJSON(val)
            }
            return .dictionary(result)

            // On Linux, the JSON deserialization handles this.
        case let asBool as Bool: // This is true on Linux.
            return .bool(asBool)
        case let asInt as Int: // This is true on Linux.
            return .int(asInt)
        case let asDouble as Double: // This is true on Linux.
            return .double(asDouble)
        case let value as [Any]:
            return .array(value.map(convertToJSON))
        case let value as [String: Any]:
            var result = [String: JSON]()
            for (key, val) in value {
                result[key] = convertToJSON(val)
            }
            return .dictionary(result)

        default:
            fatalError("unexpected object: \(object) \(type(of: object))")
        }
    }

    /// Load a JSON item from a byte string.
    ///
    //
    public init(bytes: ByteString) throws {
        do {
            let result = try JSONSerialization.jsonObject(with: Data(bytes: bytes.contents), options: [.allowFragments])

            // Convert to a native representation.
            //
            // FIXME: This is inefficient; eventually, we want a way to do the
            // loading and not need to copy / traverse all of the data multiple
            // times.
            self = JSON.convertToJSON(result)
        } catch {
            throw JSONDecodingError.malformed
        }
    }

    /// Convenience initalizer for UTF8 encoded strings.
    ///
    /// - Throws: JSONDecodingError
    public init(string: String) throws {
        let bytes = ByteString(encodingAsUTF8: string)
        try self.init(bytes: bytes)
    }
}

// MARK: - JSONSerializable helpers.

extension JSON {
    public init(_ dict: [String: JSONSerializable]) {
        self = .dictionary(Dictionary(items: dict.map({ ($0.0, $0.1.toJSON()) })))
    }
}

extension Int: JSONSerializable {
    public func toJSON() -> JSON {
        return .int(self)
    }
}

extension Double: JSONSerializable {
    public func toJSON() -> JSON {
        return .double(self)
    }
}

extension String: JSONSerializable {
    public func toJSON() -> JSON {
        return .string(self)
    }
}

extension Bool: JSONSerializable {
    public func toJSON() -> JSON {
        return .bool(self)
    }
}

extension AbsolutePath: JSONSerializable {
    public func toJSON() -> JSON {
        return .string(asString)
    }
}

extension RelativePath: JSONSerializable {
    public func toJSON() -> JSON {
        return .string(asString)
    }
}

extension Optional where Wrapped: JSONSerializable {
    public func toJSON() -> JSON {
        switch self {
        case .some(let wrapped): return wrapped.toJSON()
        case .none: return .null
        }
    }
}

extension Sequence where Iterator.Element: JSONSerializable {
    public func toJSON() -> JSON {
        return .array(map({ $0.toJSON() }))
    }
}

extension JSON: JSONSerializable {
    public func toJSON() -> JSON {
        return self
    }
}
