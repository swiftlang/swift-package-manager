/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

private let whitelist: Set<Character> = {
    Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_/:@#%+=.,".characters.map{$0})
}()

public extension String {

    /// Creates a shell escaped string. If the string does not need escaping, returns the original string.
    /// Otherwise escapes using single quotes. For eg: hello -> hello, hello$world -> 'hello$world', input A -> 'input A'
    ///
    /// - Returns: Shell escaped string.
    public func shellEscaped() -> String {
        // If all the characters in the string are in whitelist then no need to escape.
        guard let pos = characters.index(where: { !whitelist.contains($0) }) else {
            return self
        }

        // If there are no single quotes then we can just wrap the string around single quotes.
        guard let singleQuotePos = characters[pos..<characters.endIndex].index(of: "'") else {
            return "'" + self + "'"
        }

        // Otherwise iterate and escape all the single quotes.
        var newString = "'" + String(characters[characters.startIndex..<singleQuotePos])

        for char in characters[singleQuotePos..<characters.endIndex] {
            if char == "'" {
                newString += "\\'"
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
