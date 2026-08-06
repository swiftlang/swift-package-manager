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

import Testing

import TSCTestSupport

private func expectMatchImpl<Pattern, Value>(
    _ result: Bool,
    _ value: Value,
    _ pattern: Pattern,
    negativeMatch: Bool = false,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    let message: Comment
    if negativeMatch {
        message = "did not expect '\(value)' to match pattern \(pattern)"
    } else {
        message = "unexpected failure matching '\(value)' against pattern \(pattern)"
    }
    #expect(
        result,
        message,
        sourceLocation: sourceLocation,
    )
}

public func expectMatch(
    _ value: String,
    _ pattern: StringPattern,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    expectMatchImpl(
        pattern ~= value.trimmingCharacters(in: .whitespacesAndNewlines),
        value,
        pattern,
        sourceLocation: sourceLocation,
    )
}

public func expectNoMatch(
    _ value: String,
    _ pattern: StringPattern,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    expectMatchImpl(
        !(pattern ~= value.trimmingCharacters(in: .whitespacesAndNewlines)),
        value,
        pattern,
        negativeMatch: true,
        sourceLocation: sourceLocation,
    )
}
