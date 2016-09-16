/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Wrapper for exposing an item indexed by some other key type.
///
/// This is intended to be used when an algorithm wants to temporarily expose
/// some object as hashable based on a derived property (most commonly some
/// member of the object itself), without erasing the underlying object.
///
/// Example:
///
///     struct Airport {
///         // The name of the airport.
///         let name: String
///         // The names of destination airports for outgoing flights.
///         let destinations: [String]
///     }
///
///     func whereCanIGo(from here: Airport) -> [Airport] {
///         let closure = transitiveClosure([KeyedPair(airport, key: airport.name]) {
///             return $0.destinations.map{ KeyedPair($0, key: $0.name) }
///         }
///         return closure.map{ $0.item }
///     }
public struct KeyedPair<T, K: Hashable>: Hashable {
    /// The wrapped item.
    public let item: T

    /// The exposed key.
    public let key: K

    /// Create a new hashable pair for `item` indexed by `key`.
    public init(_ item: T, key: K) {
        self.item = item
        self.key = key
    }
    
    public var hashValue: Int {
        return key.hashValue
    }
}    
public func ==<T, K: Hashable>(lhs: KeyedPair<T, K>, rhs: KeyedPair<T, K>) -> Bool {
    return lhs.key == rhs.key
}
