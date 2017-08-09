/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Check if the given code unit needs shell escaping.
//
/// - Parameters:
///     - codeUnit: The code unit to be checked.
///
/// - Returns: True if shell escaping is not needed.
private func inShellWhitelist(_ codeUnit: UInt8) -> Bool {
    switch codeUnit {
        case UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "-"),
             UInt8(ascii: "_"),
             UInt8(ascii: "/"),
             UInt8(ascii: ":"),
             UInt8(ascii: "@"),
             UInt8(ascii: "%"),
             UInt8(ascii: "+"),
             UInt8(ascii: "="),
             UInt8(ascii: "."),
             UInt8(ascii: ","):
        return true
    default:
        return false
    }
}

public extension String {

    /// Creates a shell escaped string. If the string does not need escaping, returns the original string.
    /// Otherwise escapes using single quotes. For example:
    /// hello -> hello, hello$world -> 'hello$world', input A -> 'input A'
    ///
    /// - Returns: Shell escaped string.
    public func shellEscaped() -> String {

        // If all the characters in the string are in whitelist then no need to escape.
        guard let pos = utf8.index(where: { !inShellWhitelist($0) }) else {
            return self
        }

        // If there are no single quotes then we can just wrap the string around single quotes.
        guard let singleQuotePos = utf8[pos...].index(of: UInt8(ascii: "'")) else {
            return "'" + self + "'"
        }

        // Otherwise iterate and escape all the single quotes.
        var newString = "'" + String(self[..<singleQuotePos])

        for char in self[singleQuotePos...] {
            if char == "'" {
                newString += "'\\''"
            } else {
                newString += String(char)
            }
        }

        newString += "'"

        return newString
    }

    /// Shell escapes the current string. This method is mutating version of shellEscaped().
    public mutating func shellEscape() {
        self = shellEscaped()
    }
}

/// Type of localized join operator.
public enum LocalizedJoinType: String {
    /// A conjunction join operator (ie: blue, white, and red)
    case conjunction = "and"

    /// A disjunction join operator (ie: blue, white, or red)
    case disjunction = "or"
}

//FIXME: Migrate to DiagnosticFragmentBuilder
public extension Array where Element == String {
    /// Returns a localized list of terms representing a conjunction or disjunction.
    func localizedJoin(type: LocalizedJoinType) -> String {
        var result = ""
        
        for (i, item) in enumerated() {
            // Add the separator, if necessary.
            if i == count - 1 {
                switch count {
                case 1:
                    break
                case 2:
                    result += " \(type.rawValue) "
                default:
                    result += ", \(type.rawValue) "
                }
            } else if i != 0 {
                result += ", "
            }

            result += item
        }

        return result
    }
}
