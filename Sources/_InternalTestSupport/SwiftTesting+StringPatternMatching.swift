//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import TSCTestSupport

extension String {
    /// Returns `true` if the receiver matches the given `StringPattern`.
    ///
    /// Intended for use inside Swift Testing's `#expect` / `#require`, e.g.
    /// `#expect(output.matches(.contains("hello")))`.
    public func matches(_ pattern: StringPattern) -> Bool {
        pattern ~= self
    }
}

extension Optional where Wrapped == String {
    /// Returns `true` if the wrapped value exists and matches the given `StringPattern`.
    ///
    /// A `nil` receiver never matches.
    public func matches(_ pattern: StringPattern) -> Bool {
        guard let self else { return false }
        return pattern ~= self
    }
}

extension Array where Element == String {
    /// Returns `true` if the receiver matches the given sequence of `StringPattern`s.
    public func matches(_ pattern: [StringPattern]) -> Bool {
        pattern ~= self
    }
}
