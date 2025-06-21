//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.Date

/// A `Sendable` storage that allows access from concurrently running tasks in
/// an `async` closure. This type serves as a replacement for `ThreadSafeBox`
/// implemented with Swift Concurrency primitives.
public actor SendableBox<Value: Sendable> {
    public init(_ value: Value) {
        self.value = value
    }

    public var value: Value

    public func set(_ value: Value) {
        self.value = value
    }
}

extension SendableBox where Value == Int {
    package func increment() {
        self.value = value + 1
    }

    package func decrement() {
        self.value = value - 1
    }
}

extension SendableBox where Value == Date {
    package func resetDate() {
        value = Date()
    }
}
