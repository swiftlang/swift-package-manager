/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension Sequence where Element: Hashable {

    /// Finds duplicates in given sequence of Hashables.
    /// - Returns: duplicated elements in the invoking sequence.
    public func spm_findDuplicates() -> [Element] {
        var counts: [Element: Int] = [:]
        for element in self {
            counts[element, default: 0] += 1
        }
        return Array(counts.lazy.filter({ $0.value > 1 }).map({ $0.key }))
    }
}

extension Collection where Element: Hashable {

    /// Finds duplicates in given collection of Hashables.
    public func spm_findDuplicateElements() -> [[Element]] {
        var table: [Element: [Element]] = [:]
        for element in self {
            table[element, default: []].append(element)
        }
        return table.values.filter({ $0.count > 1 })
    }
}

extension Sequence {
    public func spm_findDuplicateElements<Key: Hashable>(
        by keyPath: KeyPath<Self.Element, Key>
    ) -> [[Element]] {
        return Dictionary(grouping: self, by: { $0[keyPath: keyPath] })
            .values
            .filter({ $0.count > 1 })
    }
}
