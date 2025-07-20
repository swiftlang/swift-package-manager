//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _InternalTestSupport
import Basics
import Testing

struct testisEnvironmentVariableSet {
    @Test(
        arguments: [
            (name: "", expected: false),
            (name: "DOES_NOT_EXIST", expected: false),
            (name: "HOME", expected: true)
        ]
    )
    func testisEnvironmentVariableSetReturnsExpectedValue(name: String, expected: Bool) {
        // GIVEN we have an environment variable name
        let variableName = EnvironmentKey(name)

        // WHEN we call isEnvironmentVariableSet(varaiblename)
        let actual = isEnvironmentVariableSet(variableName)

        // THEN we expect to return true
        #expect(actual == expected, "Actual is not as expected")
    }
}
