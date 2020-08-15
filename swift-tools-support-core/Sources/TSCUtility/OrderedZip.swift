// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors


/// Combine two sequences which are already ordered with respect to
/// `compare` into a single ordered sequence with the items from each
/// sequence, in order.
///
/// - Parameters:
///   - lhs: The left-hand side sequence.
///   - rhs: The right-hand side sequence.
///   - areInIncreasingOrder: A predicate that returns true if its first
///     argument should be ordered before its second argument; otherwise,
///     false. Each sequence *MUST* already be in order with respect to this
///     predicate (this is checked, in debug builds).
/// - Returns: A list of pairs, ordered with respect to `compare`. The first
/// element in the pair will come from the LHS sequence, and the second will
/// come from the RHS sequence, and equal elements appear in both lists will be
/// returned together.
@inlinable
public func orderedZip<S: Sequence>(
    _ lhs: S,
    _ rhs: S,
    by areInIncreasingOrder: (S.Element, S.Element) -> Bool
) -> [(S.Element?, S.Element?)] {
    var result: [(S.Element?, S.Element?)] = []
    result.reserveCapacity(max(lhs.underestimatedCount, rhs.underestimatedCount))

    // Initialize.
    var lhsIt = lhs.makeIterator()
    var rhsIt = rhs.makeIterator()
    var lhsItem = lhsIt.next()
    var rhsItem = rhsIt.next()

    // While each list has items...
    while let a = lhsItem, let b = rhsItem {
        // If a < b, take a.
        if areInIncreasingOrder(a, b) {
            result.append((a, nil))
            lhsItem = lhsIt.next()
            assert(lhsItem == nil || !areInIncreasingOrder(lhsItem!, a))
            continue
        }

        // If b < a, take b.
        if areInIncreasingOrder(b, a) {
            result.append((nil, b))
            rhsItem = rhsIt.next()
            assert(rhsItem == nil || !areInIncreasingOrder(rhsItem!, b))
            continue
        }

        // Otherwise, a == b, take them both.
        result.append((a, b))
        lhsItem = lhsIt.next()
        assert(lhsItem == nil || !areInIncreasingOrder(lhsItem!, a))
        rhsItem = rhsIt.next()
        assert(rhsItem == nil || !areInIncreasingOrder(rhsItem!, b))
    }

    // Add an remaining items from either list (only one of these can actually be true).
    while let a = lhsItem {
        result.append((a, nil))
        lhsItem = lhsIt.next()
        assert(lhsItem == nil || !areInIncreasingOrder(lhsItem!, a))
    }
    while let b = rhsItem {
        result.append((nil, b))
        rhsItem = rhsIt.next()
        assert(rhsItem == nil || !areInIncreasingOrder(rhsItem!, b))
    }

    return result
}

/// Combine a list of sequences which are already ordered with respect to
/// `compare` into a single ordered sequence with the items from each sequence,
/// in order.
///
/// - Parameters:
///   - sequences: The list of sequences.
///   - areInIncreasingOrder: A predicate that returns true if its first
///     argument should be ordered before its second argument; otherwise,
///     false. Each sequence *MUST* already be in order with respect to this
///     predicate (this is checked, in debug builds).
/// - Returns: A sequence of arrays, ordered with respect to `compare`. Each row
/// in the result will have exactly `sequences.count` entries, and each Nth item
/// either be nil or the equivalently ordered item from the Nth sequence.
@inlinable
public func orderedZip<S: Sequence>(
    sequences: [S],
    by areInIncreasingOrder: (S.Element, S.Element) -> Bool
) -> [[S.Element?]] {
    var result: [[S.Element?]] = []
    result.reserveCapacity(sequences.map{ $0.underestimatedCount }.max() ?? 0)

    // Initialize iterators.
    var iterators = sequences.map{ $0.makeIterator() }

    // We keep a "current" item for each iterator.
    //
    // This strategy is not particularly efficient if we have many many
    // sequences with highly varied lengths, but is simple.
    var items: [S.Element?] = []
    for i in 0 ..< iterators.count {
        items.append(iterators[i].next())
    }

    // Iterate...
    while true {
        // Find the smallest item.
        var maybeSmallest: S.Element?
        var smallestIndex: Int = -1
        for (i, itemOpt) in items.enumerated() {
            if let item = itemOpt, maybeSmallest == nil || areInIncreasingOrder(item, maybeSmallest!) {
                maybeSmallest = item
                smallestIndex = i
            }
        }

        // If there was no smallest, we have reached the end of all lists.
        guard let smallest = maybeSmallest else {
            // We are done.
            break
        }

        // Now, we have to take all items equivalent to the smallest. Since we
        // have already taken the smallest from each list, we can find this by
        // reversing the equivalence (assuming a proper predicate). We do this
        // in lieu of tracking equivalence while we iterate through the items.
        var row: [S.Element?] = []
        for (i, itemOpt) in items.enumerated() {
            // If this is the smallest item, or is not greater than the smallest
            // (and thus is equal), it should go in the list.
            if let item = itemOpt, i == smallestIndex || !areInIncreasingOrder(smallest, item) {
                // Walk the item (and validate individual sequence ordering, in debug mode).
                let next = iterators[i].next()
                assert(next == nil || !areInIncreasingOrder(next!, item))
                items[i] = next
                row.append(item)
            } else {
                // Otherwise, no entry for this sequence.
                row.append(nil)
            }
        }
        result.append(row)
    }

    return result
}
