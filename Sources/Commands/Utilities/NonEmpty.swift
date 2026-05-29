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

/// A collection guaranteed to contain at least one element.
struct NonEmpty<Element>: Sequence {
    let first: Element
    let rest: [Element]

    init(_ first: Element, _ rest: [Element] = []) {
        self.first = first
        self.rest = rest
    }

    init?(_ elements: [Element]) {
        guard let first = elements.first else { return nil }
        self.first = first
        self.rest = Array(elements.dropFirst())
    }

    func makeIterator() -> IndexingIterator<[Element]> {
        ([first] + rest).makeIterator()
    }
}
