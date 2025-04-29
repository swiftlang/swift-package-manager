/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */


import func Basics.nextItem
import Testing
@Suite
struct ArrayHelpersTests {
    @Test(
        .tags(
            Tag.TestSize.small,
        ),
        // Convert to parameterized test once https://github.com/swiftlang/swift-testing/pull/808
        // is available in a Swift toolchain.
    )
    func nextItemReturnsExpectedValue() async throws {
        #expect(nextItem(in: [0, 1, 2, 3, 4], after: 1) == 2)
        #expect(nextItem(in: [0, 1, 2, 3, 4], after: 4) == nil)
        #expect(nextItem(in: ["zero", "one", "two", "three", "four"], after: "one") == "two")
        #expect(nextItem(in: ["zero", "one", "two", "three", "four"], after: "does not exisr") == nil)
        #expect(nextItem(in: [], after: "1") == nil)
        #expect(nextItem(in: [1], after: 1) == nil)
        #expect(nextItem(in: [0, 1, 12, 1, 4], after: 1) == 12)
    }
}
