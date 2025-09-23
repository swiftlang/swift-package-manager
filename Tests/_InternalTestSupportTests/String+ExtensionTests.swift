//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _InternalTestSupport
import Testing

@Suite(
    .tags(
        .TestSize.small,
    )
)
struct StringExtensionTests {

    @Test(
        arguments: [
            (value: "", expected: false),
            (value: " ", expected: false),
            (value: "0", expected: false),
            (value: "1", expected: true),
            (value: "true", expected: true),
            (value: "True", expected: true),
            (value: "TrUe", expected: true),
            (value: "ftrue", expected: false),
            (value: "truef", expected: false),
            (value: "ftruef", expected: false),
            (value: "YES", expected: true),
            (value: "YEs", expected: true),
            (value: "yEs", expected: true),
            (value: "yes", expected: true),
            (value: "fyes", expected: false),
            (value: "yesf", expected: false),
            (value: "fyesf", expected: false),
            (value: "11", expected: false),
        ],
    )
    func isTruthyReturnsCorrectValue(
        valueUT: String,
        expected: Bool,
    ) async throws {
        let actual = valueUT.isTruthy

        #expect(actual == expected, "Value \(valueUT) should be \(expected)")
    }
}