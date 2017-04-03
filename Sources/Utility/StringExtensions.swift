/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension String {
    /**
     Remove trailing newline characters. By default chomp removes
     all trailing \n (UNIX) or all trailing \r\n (Windows) (it will
     not remove mixed occurrences of both separators.
    */
    public func chomp(separator: String? = nil) -> String {
        func scrub(_ separator: String) -> String {
            var E = endIndex
            while String(self[startIndex..<E]).hasSuffix(separator) && E > startIndex {
                E = index(before: E)
            }
            return String(self[startIndex..<E])
        }

        if let separator = separator {
            return scrub(separator)
        } else if hasSuffix("\r\n") {
            return scrub("\r\n")
        } else if hasSuffix("\n") {
            return scrub("\n")
        } else {
            return self
        }
    }

    /**
     Trims whitespace from both ends of a string, if the resulting
     string is empty, returns `nil`.String
     
     Useful because you can short-circuit off the result and thus
     handle “falsy” strings in an elegant way:
     
         return userInput.chuzzle() ?? "default value"
    */
    public func chuzzle() -> String? {
        var cc = characters

        loop: while true {
            switch cc.first {
            case nil:
                return nil
            case "\n"?, "\r"?, " "?, "\t"?, "\r\n"?:
                cc = cc.dropFirst()
            default:
                break loop
            }
        }

        loop: while true {
            switch cc.last {
            case nil:
                return nil
            case "\n"?, "\r"?, " "?, "\t"?, "\r\n"?:
                cc = cc.dropLast()
            default:
                break loop
            }
        }

        return String(cc)
    }

    /// Splits string around a delimiter string into up to two substrings
    /// If delimiter is not found, the second returned substring is nil
    public func split(around delimiter: String) -> (String, String?) {
        let comps = self.characters.split(around: Array(delimiter.characters))
        let head = String(comps.0)
        if let tail = comps.1 {
            return (head, String(tail))
        } else {
            return (head, nil)
        }
    }
}
