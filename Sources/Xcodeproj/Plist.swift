/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A enum representing data types for legacy Plist type.
/// see: https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/PropertyLists/OldStylePlists/OldStylePLists.html
enum Plist {
    case string(String)
    case array([Plist])
    case dictionary([String: Plist])
}

extension Plist: ExpressibleByStringLiteral {
    public typealias UnicodeScalarLiteralType = StringLiteralType
    public typealias ExtendedGraphemeClusterLiteralType = StringLiteralType

    public init(unicodeScalarLiteral value: UnicodeScalarLiteralType) {
        self = .string(value)
    }
    public init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterLiteralType) {
        self = .string(value)
    }
    public init(stringLiteral value: StringLiteralType) {
        self = .string(value)
    }
}

extension Plist {
    /// Serializes the Plist enum to string.
    func serialize() -> String {
        switch self {
        case .string(let str):
            return "\"" + Plist.escape(string: str) + "\""
        case .array(let items):
            return "(" + items.map({ $0.serialize() }).joined(separator: ", ") + ")"
        case .dictionary(let items):
            return "{" + items
                .sorted(by: { (lhs, rhs) in lhs.0 < rhs.0 })
                .map({ " \($0.0) = \($0.1.serialize()) " })
                .joined(separator: "; ") + "; };"
        }
    }

    /// Escapes the string for plist.
    /// Finds the instances of quote (") and backward slash (\) and prepends
    /// the escape character backward slash (\).
    static func escape(string: String) -> String {
        func needsEscape(_ char: UInt8) -> Bool {
            return char == UInt8(ascii: "\\") || char == UInt8(ascii: "\"")
        }

        guard let pos = string.utf8.index(where: needsEscape) else {
            return string
        }
        var newString = String(string.utf8[string.utf8.startIndex..<pos])!
        for char in string.utf8[pos..<string.utf8.endIndex] {
            if needsEscape(char) {
                newString += "\\"
            }
            newString += String(UnicodeScalar(char))
        }
        return newString
    }
}
