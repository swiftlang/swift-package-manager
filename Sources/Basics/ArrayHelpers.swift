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

public func nextItem<T: Equatable>(in array: [T], after item: T) -> T? {
    for (index, element) in array.enumerated() {
        if element == item {
            let nextIndex = index + 1
            return nextIndex < array.count ? array[nextIndex] : nil
        }
    }
    return nil  // Item not found or it's the last item
}

/// Determines if an array contains all elements of a subset array in any order.
/// - Parameters:
///   - array: The array to search within
///   - subset: The subset array to check for
///   - shouldBeContiguous: if `true`, the subset match must be contiguous sequenence
/// - Returns: `true` if all elements in `subset` are present in `array`, `false` otherwise
public func contains<T: Equatable>(array: [T], subset: [T], shouldBeContiguous: Bool = true) -> Bool {
    if shouldBeContiguous {
        return containsContiguousSubset(array: array, subset: subset)
    } else {
        return containsNonContiguousSubset(array: array, subset: subset)
    }
}

/// Determines if an array contains all elements of a subset array in any order.
/// - Parameters:
///   - array: The array to search within
///   - subset: The subset array to check for
/// - Returns: `true` if all elements in `subset` are present in `array`, `false` otherwise
internal func containsNonContiguousSubset<T: Equatable>(array: [T], subset: [T]) -> Bool {
    for element in subset {
        if !array.contains(element) {
            return false
        }
    }
    return true
}

/// Determines if an array contains a contiguous subsequence matching the subset array.
/// - Parameters:
///   - array: The array to search within
///   - subset: The contiguous subset array to check for
/// - Returns: `true` if `subset` appears as a contiguous subsequence in `array`, `false` otherwise
internal func containsContiguousSubset<T: Equatable>(array: [T], subset: [T]) -> Bool {
    guard !subset.isEmpty else { return true }
    guard subset.count <= array.count else { return false }

    for startIndex in 0...(array.count - subset.count) {
        var matches = true
        for (offset, element) in subset.enumerated() {
            if array[startIndex + offset] != element {
                matches = false
                break
            }
        }
        if matches {
            return true
        }
    }
    return false
}
