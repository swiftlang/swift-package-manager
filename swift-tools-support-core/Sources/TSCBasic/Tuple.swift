/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Returns true if these arrays of tuple contains the same elements.
public func ==<A: Equatable, B: Equatable>(
   lhs: [(A, B)], rhs: [(A, B)]
) -> Bool {
    guard lhs.count == rhs.count else { return false }
    for (idx, lElement) in lhs.enumerated() {
        guard lElement == rhs[idx] else {
            return false
        }
    }
    return true
}
