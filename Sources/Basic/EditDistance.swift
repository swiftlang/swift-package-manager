/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Computes the number of edits needed to transform first string to second.
///
/// - Complexity: O(_n*m_), where *n* is the length of the first String and
///   *m* is the length of the second one.
public func editDistance(_ first: String, _ second: String) -> Int {
    // FIXME: We should use the new `CollectionDifference` API once the
    // deployment target is bumped.
    let a = Array(first.utf16)
    let b = Array(second.utf16)
    var distance = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in 0...a.count {
        for j in 0...b.count {
            if i == 0 {
                distance[i][j] = j
            } else if j == 0 {
                distance[i][j] = i
            } else if a[i - 1] == b[j - 1] {
                distance[i][j] = distance[i - 1][j - 1]
            } else {
                let insertion = distance[i][ j - 1]
                let deletion = distance[i - 1][j]
                let replacement = distance[i - 1][j - 1]
                distance[i][j] = 1 + min(insertion, deletion, replacement)
            }
        }
    }
    return distance[a.count][b.count]
}

/// Finds the "best" match for a `String` from an array of possible options.
///
/// - Parameters:
///     - input: The input `String` to match.
///     - options: The available options for `input`.
///
/// - Returns: The best match from the given `options`, or `nil` if none were sufficiently close.
public func bestMatch(for input: String, from options: [String]) -> String? {
    return options
        .map { ($0, editDistance(input, $0)) }
        // Filter out unreasonable edit distances. Based on:
        // https://github.com/apple/swift/blob/37daa03b7dc8fb3c4d91dc560a9e0e631c980326/lib/Sema/TypeCheckNameLookup.cpp#L606
        .filter { $0.1 <= ($0.0.count + 2) / 3 }
        // Sort by edit distance
        .sorted { $0.1 < $1.1 }
        .first?.0
}
