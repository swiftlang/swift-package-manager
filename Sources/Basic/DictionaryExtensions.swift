/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension Dictionary {
    /// Convenience initializer to create dictionary from tuples.
    public init<S: Sequence>(items: S) where S.Iterator.Element == (Key, Value) {
        var result = Dictionary()
        for (key, value) in items {
            result[key] = value
        }
        self = result
    }
}
