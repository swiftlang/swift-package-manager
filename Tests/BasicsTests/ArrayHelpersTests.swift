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


import func Basics.nextItem
@testable import func Basics.containsNonContiguousSubset
@testable import func Basics.containsContiguousSubset
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

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func containsNonContiguousSubsetReturnsExpectedValue() async throws {
        // Empty subset should always return true
        #expect(containsNonContiguousSubset(array: [] as [String], subset: []) == true)
        #expect(containsNonContiguousSubset(array: [] as [Int], subset: []) == true)
        #expect(containsNonContiguousSubset(array: [] as [Bool], subset: []) == true)
        #expect(containsNonContiguousSubset(array: [1, 2, 3], subset: []) == true)

        // Empty array with non-empty subset should return false
        #expect(containsNonContiguousSubset(array: [] as [Int], subset: [1]) == false)

        // Single element tests
        #expect(containsNonContiguousSubset(array: [1], subset: [1]) == true)
        #expect(containsNonContiguousSubset(array: [1], subset: [2]) == false)

        // Basic subset tests - all elements present
        #expect(containsNonContiguousSubset(array: [1, 2, 3, 4, 5], subset: [1, 3, 5]) == true)
        #expect(containsNonContiguousSubset(array: [1, 2, 3, 4, 5], subset: [5, 1, 3]) == true)  // Order doesn't matter
        #expect(containsNonContiguousSubset(array: [1, 2, 3, 4, 5], subset: [2, 4]) == true)

        // Missing elements tests
        #expect(containsNonContiguousSubset(array: [1, 2, 3, 4, 5], subset: [1, 6]) == false)
        #expect(containsNonContiguousSubset(array: [1, 2, 3, 4, 5], subset: [6, 7, 8]) == false)

        // Duplicate elements in subset
        #expect(containsNonContiguousSubset(array: [1, 2, 2, 3, 4], subset: [2, 2]) == true)
        #expect(containsNonContiguousSubset(array: [1, 2, 3, 4], subset: [2, 2]) == true)  // Only one 2 in array, but still contains 2

        // String tests
        #expect(containsNonContiguousSubset(array: ["a", "b", "c", "d"], subset: ["a", "c"]) == true)
        #expect(containsNonContiguousSubset(array: ["a", "b", "c", "d"], subset: ["d", "a"]) == true)
        #expect(containsNonContiguousSubset(array: ["a", "b", "c", "d"], subset: ["e"]) == false)

        // Subset same size as array
        #expect(containsNonContiguousSubset(array: [1, 2, 3], subset: [3, 2, 1]) == true)
        #expect(containsNonContiguousSubset(array: [1, 2, 3], subset: [1, 2, 4]) == false)

        // Subset larger than array
        #expect(containsNonContiguousSubset(array: [1, 2], subset: [1, 2, 3]) == false)
    }

    @Test(
        .tags(
            Tag.TestSize.small,
        ),
    )
    func containsContiguousSubsetReturnsExpectedValue() async throws {
        // Empty subset should always return true
        #expect(containsContiguousSubset(array: [] as [String], subset: []) == true)
        #expect(containsContiguousSubset(array: [] as [Int], subset: []) == true)
        #expect(containsContiguousSubset(array: [] as [Bool], subset: []) == true)
        #expect(containsContiguousSubset(array: [1, 2, 3], subset: []) == true)

        // Empty array with non-empty subset should return false
        #expect(containsContiguousSubset(array: [] as [Int], subset: [1]) == false)

        // Single element tests
        #expect(containsContiguousSubset(array: [1], subset: [1]) == true)
        #expect(containsContiguousSubset(array: [1], subset: [2]) == false)

        // Basic contiguous subset tests
        #expect(containsContiguousSubset(array: [1, 2, 3, 4, 5], subset: [2, 3, 4]) == true)
        #expect(containsContiguousSubset(array: [1, 2, 3, 4, 5], subset: [1, 2]) == true)
        #expect(containsContiguousSubset(array: [1, 2, 3, 4, 5], subset: [4, 5]) == true)
        #expect(containsContiguousSubset(array: [1, 2, 3, 4, 5], subset: [1, 2, 3, 4, 5]) == true)  // Entire array

        // Non-contiguous elements should return false
        #expect(containsContiguousSubset(array: [1, 2, 3, 4, 5], subset: [1, 3, 5]) == false)
        #expect(containsContiguousSubset(array: [1, 2, 3, 4, 5], subset: [2, 4]) == false)
        #expect(containsContiguousSubset(array: [1, 2, 3, 4, 5], subset: [1, 3]) == false)

        // Wrong order should return false
        #expect(containsContiguousSubset(array: [1, 2, 3, 4, 5], subset: [3, 2, 1]) == false)
        #expect(containsContiguousSubset(array: [1, 2, 3, 4, 5], subset: [5, 4, 3]) == false)

        // Missing elements
        #expect(containsContiguousSubset(array: [1, 2, 3, 4, 5], subset: [1, 6]) == false)
        #expect(containsContiguousSubset(array: [1, 2, 3, 4, 5], subset: [6, 7]) == false)

        // Duplicate elements
        #expect(containsContiguousSubset(array: [1, 2, 2, 3, 4], subset: [2, 2, 3]) == true)
        #expect(containsContiguousSubset(array: [1, 2, 3, 2, 4], subset: [2, 2]) == false)  // 2s are not contiguous
        #expect(containsContiguousSubset(array: [1, 1, 2, 3], subset: [1, 1]) == true)

        // String tests
        #expect(containsContiguousSubset(array: ["a"], subset: ["b", "c"]) == false)
        #expect(containsContiguousSubset(array: ["a"], subset: []) == true)
        #expect(containsContiguousSubset(array: ["a", "b", "c", "d"], subset: ["b", "c"]) == true)
        #expect(containsContiguousSubset(array: ["a", "b", "c", "d"], subset: ["a", "c"]) == false)  // Not contiguous
        #expect(containsContiguousSubset(array: ["hello", "world", "test"], subset: ["world", "test"]) == true)

        // Subset larger than array
        #expect(containsContiguousSubset(array: [1, 2], subset: [1, 2, 3]) == false)

        // Multiple occurrences - should find first match
        #expect(containsContiguousSubset(array: [1, 2, 3, 1, 2, 3], subset: [1, 2]) == true)
        #expect(containsContiguousSubset(array: [1, 2, 3, 1, 2, 3], subset: [2, 3]) == true)

        // Edge case: subset at the end
        #expect(containsContiguousSubset(array: [1, 2, 3, 4], subset: [3, 4]) == true)

        // Edge case: subset at the beginning
        #expect(containsContiguousSubset(array: [1, 2, 3, 4], subset: [1, 2]) == true)
    }
}
