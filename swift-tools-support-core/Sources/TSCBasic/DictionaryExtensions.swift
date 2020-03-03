/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension Dictionary {
    /// Returns a new dictionary containing the keys of this dictionary with the
    /// values transformed by the given closure, if transformed is not nil.
    public func spm_flatMapValues<T>(_ transform: (Value) throws -> T?) rethrows -> [Key: T] {
        var transformed: [Key: T] = [:]
        for (key, value) in self {
            if let value = try transform(value) {
                transformed[key] = value
            }
        }
        return transformed
    }
}

extension Array {
    /// Create a dictionary with given sequence of elements.
    public func spm_createDictionary<Key: Hashable, Value>(
        _ uniqueKeysWithValues: (Element) -> (Key, Value)
    ) -> [Key: Value] {
        return Dictionary(uniqueKeysWithValues: self.map(uniqueKeysWithValues))
    }
}
