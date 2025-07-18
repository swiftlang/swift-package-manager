//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A wrapper for a dictionary that stores the transitively enabled traits for each package.
public struct EnabledTraitsMap: ExpressibleByDictionaryLiteral {
    public typealias Key = PackageIdentity
    public typealias Value = Set<String>

    var storage: [PackageIdentity: Set<String>] = [:]

    public init() { }

    public init(dictionaryLiteral elements: (Key, Value)...) {
        for (key, value) in elements {
            storage[key] = value
        }
    }

    public init(_ dictionary: [Key: Value]) {
        self.storage = dictionary
    }

    public subscript(key: PackageIdentity) -> Set<String> {
        get { storage[key] ?? ["default"] }
        set { storage[key] = newValue }
    }

    public var dictionaryLiteral: [PackageIdentity: Set<String>] {
        return storage
    }
}
