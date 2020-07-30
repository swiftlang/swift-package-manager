/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/// Typealias for an any typed dictionary for arbitrary usage to store context.
public typealias Context = [ObjectIdentifier: Any]

extension Context {
    /// Get the value for the given type.
    public func get<T>(_ type: T.Type = T.self) -> T {
        guard let value = getOptional(type) else {
            fatalError("no type \(T.self) in context")
        }
        return value
    }

    /// Get the value for the given type, if present.
    public func getOptional<T>(_ type: T.Type = T.self) -> T? {
        guard let value = self[ObjectIdentifier(T.self)] else {
            return nil
        }
        return value as? T
    }

    /// Set a context value for a type.
    public mutating func set<T>(_ value: T) {
        self[ObjectIdentifier(T.self)] = value
    }
}
