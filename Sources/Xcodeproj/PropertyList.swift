/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A enum representing data types for legacy PropertyList type.
/// Note that the `identifier` enum is not strictly necessary,
/// but useful to semantically distinguish the strings that
/// represents object identifiers from those that are just data.
/// see: https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/PropertyLists/OldStylePlists/OldStylePLists.html
public enum PropertyList {
    case identifier(String)
    case string(String)
    case array([PropertyList])
    case dictionary([String: PropertyList])

    var string: String? {
        if case .string(let string) = self {
            return string
        }
        return nil
    }

    var array: [PropertyList]? {
        if case .array(let array) = self {
            return array
        }
        return nil
    }
}

extension PropertyList: ExpressibleByStringLiteral {
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

extension PropertyList: CustomStringConvertible {
    public var description: String {
        return serialize()
    }
}

extension PropertyList {
    /// Serializes the Plist enum to string.
    public func serialize() -> String {
        return generatePlistRepresentation(plist: self, indentation: Indentation())
    }

    /// Escapes the string for plist.
    /// Finds the instances of quote (") and backward slash (\) and prepends
    /// the escape character backward slash (\).
    static func escape(string: String) -> String {
        func needsEscape(_ char: UInt8) -> Bool {
            return char == UInt8(ascii: "\\") || char == UInt8(ascii: "\"")
        }

        guard let pos = string.utf8.firstIndex(where: needsEscape) else {
            return string
        }
        var newString = String(string[..<pos])
        for char in string.utf8[pos...] {
            if needsEscape(char) {
                newString += "\\"
            }
            newString += String(UnicodeScalar(char))
        }
        return newString
    }
}

extension PropertyList {
    /// Private struct to generate indentation strings.
    fileprivate struct Indentation: CustomStringConvertible {
        var level: Int = 0
        mutating func increase() {
            level += 1
            precondition(level > 0, "indentation level overflow")
        }
        mutating func decrease() {
            precondition(level > 0, "indentation level underflow")
            level -= 1
        }
        var description: String {
            return String(repeating: "   ", count: level)
        }
    }

    /// Private function to generate OPENSTEP-style plist representation.
    fileprivate func generatePlistRepresentation(plist: PropertyList, indentation: Indentation) -> String {
        // Do the appropriate thing for each type of plist node.
        switch plist {

          case .identifier(let ident):
            // FIXME: we should assert that the identifier doesn't need quoting
            return ident

          case .string(let string):
            return "\"" + PropertyList.escape(string: string) + "\""

          case .array(let array):
            var indent = indentation
            var str = "(\n"
            indent.increase()
            for (i, item) in array.enumerated() {
                str += "\(indent)\(generatePlistRepresentation(plist: item, indentation: indent))"
                str += (i != array.count - 1) ? ",\n" : "\n"
            }
            indent.decrease()
            str += "\(indent))"
            return str

          case .dictionary(let dict):
            var indent = indentation
            let dict = dict.sorted(by: {
                // Make `isa` sort first (just for readability purposes).
                switch ($0.key, $1.key) {
                  case ("isa", "isa"): return false
                  case ("isa", _): return true
                  case (_, "isa"): return false
                  default: return $0.key < $1.key
                }
            })
            var str = "{\n"
            indent.increase()
            for item in dict {
                str += "\(indent)\(item.key) = \(generatePlistRepresentation(plist: item.value, indentation: indent));\n"
            }
            indent.decrease()
            str += "\(indent)}"
            return str
        }
    }
}
