/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A very minimal JSON type to serialize the manifest.
enum JSON {
    case null
    case int(Int)
    case double(Double)
    case bool(Bool)
    case string(String)
    case array([JSON])
    case dictionary([String: JSON])
}

extension JSON {
    /// Converts the JSON to string representation.
    // FIXME: No escaping implemented for now.
    func toString() -> String {
        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .int(let value):
            return value.description
        case .double(let value):
            return value.debugDescription
        case .string(let value):
            return "\"" + value + "\""
        case .array(let contents):
            return "[" + contents.map({ $0.toString() }).joined(separator: ", ") + "]"
        case .dictionary(let contents):
            var output = "{"
            for (i, key) in contents.keys.sorted().enumerated() {
                if i != 0 { output += ", " }
                output += "\"" + key + "\"" + ": " + contents[key]!.toString()
            }
            output += "}"
            return output
        }
    }
}
