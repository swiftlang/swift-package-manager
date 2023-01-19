//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public struct HTTPClientHeaders: Sendable {
    private var items: [Item]
    private var headers: [String: [String]]

    public init(_ items: [Item] = []) {
        self.items = items
        self.headers = items.reduce([String: [String]]()) { partial, item in
            var map = partial
            // Avoid copy-on-write: remove entry from dictionary before mutating
            var values = map.removeValue(forKey: item.name.lowercased()) ?? []
            values.append(item.value)
            map[item.name.lowercased()] = values
            return map
        }
    }

    public func contains(_ name: String) -> Bool {
        self.headers[name.lowercased()] != nil
    }

    public var count: Int {
        self.headers.count
    }

    public mutating func add(name: String, value: String) {
        self.add(Item(name: name, value: value))
    }

    public mutating func add(_ item: Item) {
        self.add([item])
    }

    public mutating func add(_ items: [Item]) {
        for item in items {
            if self.items.contains(item) {
                continue
            }
            // Avoid copy-on-write: remove entry from dictionary before mutating
            var values = self.headers.removeValue(forKey: item.name.lowercased()) ?? []
            values.append(item.value)
            self.headers[item.name.lowercased()] = values
            self.items.append(item)
        }
    }

    public mutating func merge(_ other: HTTPClientHeaders) {
        self.add(other.items)
    }

    public func get(_ name: String) -> [String] {
        self.headers[name.lowercased()] ?? []
    }

    public struct Item: Equatable, Sendable {
        let name: String
        let value: String

        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }
}

extension HTTPClientHeaders: Sequence {
    public func makeIterator() -> IndexingIterator<[Item]> {
        self.items.makeIterator()
    }
}

extension HTTPClientHeaders: Equatable {
    public static func == (lhs: HTTPClientHeaders, rhs: HTTPClientHeaders) -> Bool {
        lhs.headers == rhs.headers
    }
}

extension HTTPClientHeaders: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, String)...) {
        self.init(elements.map(Item.init))
    }
}
