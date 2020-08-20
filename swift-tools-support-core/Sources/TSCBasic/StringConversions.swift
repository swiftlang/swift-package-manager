/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
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
  #if os(Windows)
    if codeUnit == UInt8(ascii: "\\") {
        return true
    }
  #endif
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

extension String {

    /// Creates a shell escaped string. If the string does not need escaping, returns the original string.
    /// Otherwise escapes using single quotes on Unix and double quotes on Windows. For example:
    /// hello -> hello, hello$world -> 'hello$world', input A -> 'input A'
    ///
    /// - Returns: Shell escaped string.
    public func spm_shellEscaped() -> String {

        // If all the characters in the string are in whitelist then no need to escape.
        guard let pos = utf8.firstIndex(where: { !inShellWhitelist($0) }) else {
            return self
        }

      #if os(Windows)
        let quoteCharacter: Character = "\""
        let escapedQuoteCharacter = "\"\""
      #else
        let quoteCharacter: Character = "'"
        let escapedQuoteCharacter = "'\\''"
      #endif
        // If there are no quote characters then we can just wrap the string within the quotes.
        guard let quotePos = utf8[pos...].firstIndex(of: quoteCharacter.asciiValue!) else {
            return String(quoteCharacter) + self + String(quoteCharacter)
        }

        // Otherwise iterate and escape all the single quotes.
        var newString = String(quoteCharacter) + String(self[..<quotePos])

        for char in self[quotePos...] {
            if char == quoteCharacter {
                newString += escapedQuoteCharacter
            } else {
                newString += String(char)
            }
        }

        newString += String(quoteCharacter)

        return newString
    }

    /// Shell escapes the current string. This method is mutating version of shellEscaped().
    public mutating func spm_shellEscape() {
        self = spm_shellEscaped()
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
    func spm_localizedJoin(type: LocalizedJoinType) -> String {
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
