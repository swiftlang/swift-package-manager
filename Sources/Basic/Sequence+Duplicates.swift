/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public extension Sequence where Iterator.Element: Hashable {
    // Returns the set of duplicate elements in two arrays, if any.
    func duplicates(_ other: [Iterator.Element]) -> Set<Iterator.Element>? {
        let dupes = Set(self).intersection(Set(other))
        return dupes.isEmpty ? nil : dupes
    }

    func duplicates() -> [Iterator.Element] {
        var unique = Set<Iterator.Element>()
        var duplicate = Array<Iterator.Element>()

        for element in self {
            guard !unique.contains(element) else {
                duplicate.append(element)
                continue
            }

            unique.insert(element)
        }

        return duplicate
    }
}
