/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
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
extension JSON: Equatable { }
public func ==(lhs: JSON, rhs: JSON) -> Bool {
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

// MARK: JSON Encoding

extension JSON {
    /// Encode a JSON item into a string of bytes.
    public func toBytes() -> ByteString {
        return (OutputByteStream() <<< self).bytes
    }

}

/// Support writing to a byte stream.
extension JSON: ByteStreamable {
    public func write(to stream: OutputByteStream) {
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
            // FIXME: OutputByteStream should just let us do this via conformances.
            stream <<< "["
            for (i, item) in contents.enumerated() {
                if i != 0 { stream <<< ", " }
                stream <<< item
            }
            stream <<< "]"
        case .dictionary(let contents):
            // We always output in a deterministic order.
            //
            // FIXME: OutputByteStream should just let us do this via conformances.
            stream <<< "{"
            for (i, key) in contents.keys.sorted().enumerated() {
                if i != 0 { stream <<< ", " }
                stream <<< Format.asJSON(key) <<< ": " <<< contents[key]!
            }
            stream <<< "}"
        }
    }
}
