/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation


extension String {
    /**
     Remove trailing newline characters. By default chomp removes
     all trailing \n (UNIX) or all trailing \r\n (Windows) (it will
     not remove mixed occurrences of both separators.
    */
    public func spm_chomp(separator: String? = nil) -> String {
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
    public func spm_chuzzle() -> String? {
        var cc = self

        loop: while true {
            switch cc.first {
            case nil:
                return nil
            case "\n"?, "\r"?, " "?, "\t"?, "\r\n"?:
                cc = String(cc.dropFirst())
            default:
                break loop
            }
        }

        loop: while true {
            switch cc.last {
            case nil:
                return nil
            case "\n"?, "\r"?, " "?, "\t"?, "\r\n"?:
                cc = String(cc.dropLast())
            default:
                break loop
            }
        }

        return String(cc)
    }

    /// Splits string around a delimiter string into up to two substrings
    /// If delimiter is not found, the second returned substring is nil
    public func spm_split(around delimiter: String) -> (String, String?) {
        let comps = self.spm_split(around: Array(delimiter))
        let head = String(comps.0)
        if let tail = comps.1 {
            return (head, String(tail))
        } else {
            return (head, nil)
        }
    }

    /// Drops the given suffix from the string, if present.
    public func spm_dropSuffix(_ suffix: String) -> String {
        if hasSuffix(suffix) {
           return String(dropLast(suffix.count))
        }
        return self
    }

    public func spm_dropGitSuffix() -> String {
        return spm_dropSuffix(".git")
    }

    public func spm_multilineIndent(count: Int) -> String {
        let indent = String(repeating: " ", count: count)
        return self
            .split(separator: "\n")
            .map { indent + $0 }
            .joined(separator: "\n")
    }

    @inlinable
    public init(tsc_fromUTF8 bytes: Array<UInt8>) {
        if let string = bytes.withContiguousStorageIfAvailable({ bptr in
            String(decoding: bptr, as: UTF8.self)
        }) {
            self = string
        } else {
            self = bytes.withUnsafeBufferPointer { ubp in
                String(decoding: ubp, as: UTF8.self)
            }
        }
    }

    @inlinable
    public init(tsc_fromUTF8 bytes: ArraySlice<UInt8>) {
        if let string = bytes.withContiguousStorageIfAvailable({ bptr in
            String(decoding: bptr, as: UTF8.self)
        }) {
            self = string
        } else {
            self = bytes.withUnsafeBufferPointer { ubp in
                String(decoding: ubp, as: UTF8.self)
            }
        }
    }

    @inlinable
    public init(tsc_fromUTF8 bytes: Data) {
        self = String(decoding: bytes, as: UTF8.self)
    }

}
