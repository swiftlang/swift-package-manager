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
    package init(_ value: Value? = nil) {
        self.value = value
    }

    package var value: Value?
}

extension SendableBox where Value == Int {
    package func increment() {
        if let value {
            self.value = value + 1
        }
    }

    package func decrement() {
        if let value {
            self.value = value - 1
        }
    }
}

extension SendableBox where Value == Date {
    package func resetDate() {
        value = Date()
    }
}
