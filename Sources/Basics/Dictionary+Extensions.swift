/*
 This source file is part of the Swift.org open source project
 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic

extension Dictionary {
    @inlinable
    @discardableResult
    public mutating func memoize(key: Key, body: () throws -> Value) rethrows -> Value {
        if let value = self[key] {
            return value
        }
        let value = try body()
        self[key] = value
        return value
    }
}
