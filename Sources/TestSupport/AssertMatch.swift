/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import struct Basic.RegEx

public indirect enum StringPattern {
    /// Matches only the start, when matching a list of inputs.
    case start
    
    /// Matches only the end, when matching a list of inputs.
    case end
    
    /// Matches any sequence of zero or more strings, when matched a list of inputs.
    case anySequence
    
    case any
    case contains(String)
    case equal(String)
    case regex(String)
    case prefix(String)
    case suffix(String)
    case and(StringPattern, StringPattern)
    case or(StringPattern, StringPattern)
}

extension StringPattern: ExpressibleByStringLiteral {
    public typealias UnicodeScalarLiteralType = StringLiteralType
    public typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
    
    public init(unicodeScalarLiteral value: UnicodeScalarLiteralType) {
        self = .equal(value)
    }
    public init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterLiteralType) {
        self = .equal(value)
    }
    public init(stringLiteral value: StringLiteralType) {
        self = .equal(value)
    }
}

public func ~=(pattern: StringPattern, value: String) -> Bool {
    switch pattern {
        // These cases never matches individual items, they are just used for matching string lists.
    case .start, .end, .anySequence:
        return false

    case .any:
        return true
    case .contains(let needle):
        return value.contains(needle)
    case .equal(let needle):
        return value == needle
    case .regex(let pattern):
        return try! !RegEx(pattern: pattern).matchGroups(in: value).isEmpty
    case .prefix(let needle):
        return value.hasPrefix(needle)
    case .suffix(let needle):
        return value.hasSuffix(needle)
    case let .and(lhs, rhs):
        return lhs ~= value && rhs ~= value
    case let .or(lhs, rhs):
        return lhs ~= value || rhs ~= value
    }
}

public func ~=(patterns: [StringPattern], input: [String]) -> Bool {
    let startIndex = input.startIndex
    let endIndex = input.endIndex

    /// Helper function to match at a specific location.
    func match(_ patterns: Array<StringPattern>.SubSequence, onlyAt input: Array<String>.SubSequence) -> Bool {
        // If we have read all the pattern, we are done.
        guard let item = patterns.first else { return true }
        let patterns = patterns.dropFirst()
        
        // Otherwise, match the first item and recurse.
        switch item {
        case .start:
            if input.startIndex != startIndex { return false }
            return match(patterns, onlyAt: input)
            
        case .end:
            if input.startIndex != endIndex { return false }
            return match(patterns, onlyAt: input)
            
        case .anySequence:
            return matchAny(patterns, input: input)

        default:
            if input.isEmpty || !(item ~= input.first!) { return false }
            return match(patterns, onlyAt: input.dropFirst())
        }
    }
    
    /// Match a pattern at any position in the input
    func matchAny(_ patterns: Array<StringPattern>.SubSequence, input: Array<String>.SubSequence) -> Bool {
        if match(patterns, onlyAt: input) {
            return true
        }
        if input.isEmpty {
            return false
        }
        return matchAny(patterns, input: input.dropFirst())
    }
    
    return matchAny(patterns[...], input: input[...])
}

private func XCTAssertMatchImpl<Pattern, Value>(_ result: Bool, _ value: Value, _ pattern: Pattern, file: StaticString, line: UInt) {
    XCTAssert(result, "unexpected failure matching '\(value)' against pattern \(pattern)", file: file, line: line)
}

public func XCTAssertMatch(_ value: String, _ pattern: StringPattern, file: StaticString = #file, line: UInt = #line) {
    XCTAssertMatchImpl(pattern ~= value, value, pattern, file: file, line: line)
}
public func XCTAssertNoMatch(_ value: String, _ pattern: StringPattern, file: StaticString = #file, line: UInt = #line) {
    XCTAssertMatchImpl(!(pattern ~= value), value, pattern, file: file, line: line)
}

public func XCTAssertMatch(_ value: String?, _ pattern: StringPattern, file: StaticString = #file, line: UInt = #line) {
    guard let value = value else {
        return XCTFail("unexpected nil value for match against pattern: \(pattern)")
    }
    XCTAssertMatchImpl(pattern ~= value, value, pattern, file: file, line: line)
}
public func XCTAssertNoMatch(_ value: String?, _ pattern: StringPattern, file: StaticString = #file, line: UInt = #line) {
    guard let value = value else { return }
    XCTAssertMatchImpl(!(pattern ~= value), value, pattern, file: file, line: line)
}

public func XCTAssertMatch(_ value: [String], _ pattern: [StringPattern], file: StaticString = #file, line: UInt = #line) {
    XCTAssertMatchImpl(pattern ~= value, value, pattern, file: file, line: line)
}
public func XCTAssertNoMatch(_ value: [String], _ pattern: [StringPattern], file: StaticString = #file, line: UInt = #line) {
    XCTAssertMatchImpl(!(pattern ~= value), value, pattern, file: file, line: line)
}
