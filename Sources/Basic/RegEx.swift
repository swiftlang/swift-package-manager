/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation

public struct RegEx {
    private let regex: NSRegularExpression
    public typealias Options = NSRegularExpression.Options
    
    public init(pattern: String, options: Options = []) throws {
        self.regex = try NSRegularExpression(pattern: pattern, options: options)
    }
    
    /// Returns match groups for each match. E.g.:
    ///
    /// RegEx(pattern: "([a-z]+)([0-9]+)").matchGroups(in: "foo1 bar2 baz3") -> [["foo", "1"], ["bar", "2"], ["baz", "3"]]
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
