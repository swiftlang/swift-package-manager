/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation

/// A helpful wrapper around NSRegularExpression
/// - SeeAlso: NSRegularExpression
public struct RegEx {
    private let regex: NSRegularExpression
    public typealias Options = NSRegularExpression.Options
    
    /// Creates a new Regex using `pattern`
    ///
    /// - Parameters:
    ///     - pattern: A valid Regular Expression pattern
    ///     - options: NSRegularExpression.Options on how the RegEx should be processed.
    /// - Note: Deliminators must be double escaped. Once for Swift and once for RegEx
    ///   Example, to math a negative integer: `RegEx(pattern: "-\d")` -> `RegEx(pattern: "-\\d")`
    /// - SeeAlso: NSRegularExpression
    /// - Throws: An Error if `pattern` is an invalid Regular Expression
    public init(pattern: String, options: Options = []) throws {
        self.regex = try NSRegularExpression(pattern: pattern, options: options)
    }
    
    /// Returns match groups for every match of the Regex.
    ///
    /// For every match in the string, it constructs the collection
    /// of groups matched.
    ///
    ///     RegEx(pattern: "([a-z]+)([0-9]+)").matchGroups(in: "foo1 bar2 baz3")
    ///
    /// Returns `[["foo", "1"], ["bar", "2"], ["baz", "3"]]`
    ///
    /// - Parameters:
    ///     - in: A string to check for matches to the whole Regex
    /// - Returns: A collection where each elements is the collection of matched groups.
    public func matchGroups(in string: String) -> [[String]] {
        let nsString = NSString(string: string)
        
        return regex.matches(in: string, options: [], range: NSMakeRange(0, nsString.length)).map{ match -> [String] in
            return (1 ..< match.numberOfRanges).map { idx -> String in
                let range = match.range(at: idx)
                return range.location == NSNotFound ? "" : nsString.substring(with: range)
            }
        }
    }
}
