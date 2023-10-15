//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A result which can be loaded.
///
/// It is useful for objects that hold a state on disk and need to be
/// loaded frequently.
public final class LoadableResult<Value> {
    /// The constructor closure for the value.
    private let construct: () throws -> Value

    /// Create a loadable result.
    public init(_ construct: @escaping () throws -> Value) {
        self.construct = construct
    }

    /// Load and return the result.
    public func loadResult() -> Result<Value, Error> {
        Result(catching: {
            try self.construct()
        })
    }

    /// Load and return the value.
    public func load() throws -> Value {
        try self.loadResult().get()
    }
}
