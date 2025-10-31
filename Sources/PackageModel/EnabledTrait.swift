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

import Basics

// MARK: - EnabledTraitsMap

/// A wrapper struct for a dictionary that stores the transitively enabled traits for each package.
/// This struct implicitly omits adding `default` traits to its storage, and returns `nil` if it there is no existing entry for
/// a given package, since if there are no explicitly enabled traits set by anything else a package will then default to its `default` traits,
/// if they exist.
public struct EnabledTraitsMap {
    public typealias Key = PackageIdentity
    public typealias Value = EnabledTraits

    private var storage: ThreadSafeKeyValueStore<PackageIdentity, EnabledTraits> = .init()

    public init() { }

    public subscript(key: PackageIdentity) -> EnabledTraits {
        get { storage[key] ?? ["default"] }
        set {
            // Omit adding "default" explicitly, since the map returns "default"
            // if there is no explicit traits declared. This will allow us to check
            // for nil entries in the stored dictionary, which tells us whether
            // traits have been explicitly declared.
            guard newValue != ["default"] else { return }
            if storage[key] == nil {
                storage[key] = newValue
            } else {
                storage[key]?.formUnion(newValue)
            }
        }
    }

    /// Returns a list of traits that were explicitly enabled for a given package.
    public subscript(explicitlyEnabledTraitsFor key: PackageIdentity) -> EnabledTraits? {
        get { storage[key] }
    }

    /// Returns a dictionary literal representation of the map.
    public var dictionaryLiteral: [PackageIdentity: EnabledTraits] {
        return storage.get()
    }
}

// MARK: EnabledTraitsMap + ExpressibleByDictionaryLiteral
extension EnabledTraitsMap: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (Key, Value)...) {
        for (key, value) in elements {
            storage[key] = value
        }
    }

    public init(_ dictionary: [Key: Value]) {
        self.storage = .init(dictionary)
    }
}

// MARK: - EnabledTrait

/// A structure representing a trait that is enabled. The package in which this is enabled on is identified in
/// the EnabledTraitsMap.
///
/// An enabled trait is a trait that is either explicitly enabled by a user-passed trait configuration from the command line,
/// a parent package that has defined enabled traits for its dependency package, or transitively by another trait (including the default case).
///
/// An `EnabledTrait` is differentiated by its `name`, and all other data stored in this struct is treated as metadata for
/// convenience. When unifying two `EnabledTrait`s, it will combine the list of setters if the `name`s match.
///
public struct EnabledTrait: Identifiable {
    /// Convenience typealias for a list of `Setter`
    public typealias Setters = Set<Setter>

    /// The identifier for the trait.
    public var id: String { name }

    /// The name of the trait.
    public let name: String

    /// The list of setters who have enabled this trait.
    public var setters: Setters = []

    public init(name: String, setBy: Setter) {
        self.name = name
        self.setters = [setBy]
    }

    public init(name: String, setBy: [Setter]) {
        self.name = name
        self.setters = Set(setBy)
    }

    /// The packages that have enabled this trait.
    public var parentPackages: [Manifest.PackageIdentifier] {
        setters.compactMap(\.parentPackage)
    }

    public var isDefault: Bool {
        name == "default"
    }

    /// Returns a new `EnabledTrait` that contains a merged list of `Setters` from
    /// `self` and the `otherTrait`, only if the traits are equal. Otherwise, returns nil.
    /// - Parameter otherTrait: The trait to merge in.
    public func unify(_ otherTrait: EnabledTrait) -> EnabledTrait? {
        guard self.name == otherTrait.name else {
            return nil
        }

        var updatedTrait = self
        updatedTrait.setters = setters.union(otherTrait.setters)
        return updatedTrait
    }
}

// MARK: EnabledTrait.Setter

extension EnabledTrait {
    /// An enumeration that describes how a given trait was set as enabled.
    public enum Setter: Hashable, CustomStringConvertible {
        case traitConfiguration
        case package(Manifest.PackageIdentifier)
        case trait(String)

        public var description: String {
            switch self {
            case .traitConfiguration:
                "command-line trait configuration"
            case .package(let parent):
                "parent package: \(parent.description)"
            case .trait(let trait):
                "trait: \(trait)"
            }
        }

        /// The identifier of the parent package that defined this trait, if any.
        public var parentPackage: Manifest.PackageIdentifier? {
            switch self {
            case .package(let id):
                return id
            case .traitConfiguration, .trait:
                return nil
            }
        }

        public static var `default`: Self {
            .trait("default")
        }
    }
}

// MARK: EnabledTrait + Equatable

extension EnabledTrait: Equatable {
    // When comparing two `EnabledTraits`, if the names are the same then
    // we know that these two objects are referring to the same trait of a package.
    // In this case, the two objects should be combined into one.
    public static func ==(lhs: EnabledTrait, rhs: EnabledTrait) -> Bool {
        return lhs.name == rhs.name
    }

    public static func ==(lhs: EnabledTrait, rhs: String) -> Bool {
        return lhs.name == rhs
    }

    public static func ==(lhs: String, rhs: EnabledTrait) -> Bool {
        return lhs == rhs.name
    }
}

// MARK: EnabledTrait + Comparable

extension EnabledTrait: Comparable {
    public static func <(lhs: EnabledTrait, rhs: EnabledTrait) -> Bool {
        return lhs.name < rhs.name
    }
}

// MARK: EnabledTrait + CustomStringConvertible

extension EnabledTrait: CustomStringConvertible {
    public var description: String {
        name
    }
}

// MARK: EnabledTrait + ExpressibleByStringLiteral

extension EnabledTrait: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.name = value
    }
}

// MARK: - EnabledTraits

/// A collection wrapper around a set of `EnabledTrait` instances that provides specialized behavior
/// for trait management. This struct ensures that traits with the same name are automatically unified
/// by merging their setters when inserted, maintaining a single entry per unique trait name. It provides
/// convenient set operations like union and intersection, along with collection protocol conformance for
/// easy iteration and manipulation of enabled traits.
public struct EnabledTraits: Hashable {
    public typealias Element = EnabledTrait
    public typealias Index = IdentifiableSet<Element>.Index

    private var _traits: IdentifiableSet<EnabledTrait> = []

    public static var defaults: EnabledTraits {
        ["default"]
    }

    public init<C: Collection>(_ traits: C, setBy origin: EnabledTrait.Setter) where C.Element == String {
        let enabledTraits = traits.map({ EnabledTrait(name: $0, setBy: origin) })
        self.init(enabledTraits)
    }

    public init<C: Collection>(_ traits: C) where C.Element == EnabledTrait {
        self._traits = IdentifiableSet(traits)
    }

    public static func ==(_ lhs: EnabledTraits, _ rhs: EnabledTraits) -> Bool {
        lhs._traits.names == rhs._traits.names
    }
}

// MARK: EnabledTraits + ExpressibleByArrayLiteral

extension EnabledTraits: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Element...) {
        for element in elements {
            _traits.insert(element)
        }
    }
}

// MARK: EnabledTraits + Collection

extension EnabledTraits: Collection {
    public var startIndex: Index {
        return _traits.startIndex
    }

    public var endIndex: Index {
        return _traits.endIndex
    }

    public func index(after i: Index) -> Index {
        return _traits.index(after: i)
    }

    public subscript(position: Index) -> Element {
        return _traits[position]
    }

    public mutating func insert(_ newMember: Element) {
        _traits.insert(newMember)
    }

    public mutating func remove(_ member: Element) -> Element? {
        return _traits.remove(member)
    }

    public func contains(_ member: Element) -> Bool {
        return _traits.contains(member)
    }

    public func intersection<C: Collection>(_ other: C) -> EnabledTraits where C.Element == String {
        self.intersection(other.map(\.asEnabledTrait))
    }

    public func intersection<C: Collection>(_ other: C) -> EnabledTraits where C.Element == Self.Element {
        let otherSet = IdentifiableSet(other.map({ $0 }))
        let intersection = self._traits.intersection(otherSet)
        return EnabledTraits(intersection)
    }

    public func union(_ other: EnabledTraits) -> EnabledTraits {
        let unionedTraits = _traits.union(other)
        return EnabledTraits(unionedTraits)
    }

    public mutating func formUnion(_ other: EnabledTraits) {
        self._traits = self.union(other)._traits
    }

    public func map(_ transform: (Self.Element) throws -> Self.Element) rethrows -> EnabledTraits {
        let transformedTraits = try _traits.map(transform)
        return EnabledTraits(transformedTraits)
    }

    public func flatMap(_ transform: (Self.Element) throws -> EnabledTraits) rethrows -> EnabledTraits {
        let transformedTraits = try _traits.flatMap(transform)
        return EnabledTraits(transformedTraits)
    }

    public static func ==<C: Collection>(_ lhs: EnabledTraits, _ rhs: C) -> Bool where C.Element == Element {
        lhs._traits.names == rhs.names
    }

    public static func ==<C: Collection>(_ lhs: C, _ rhs: EnabledTraits) -> Bool where C.Element == Element {
        lhs.names == rhs._traits.names
    }
}

// MARK: - EnabledTraitConvertible

/// Represents a type that can be converted into an `EnabledTrait`.
/// This protocol enables conversion between string-like types and `EnabledTrait` instances,
/// allowing for more flexible APIs that can accept either strings or traits interchangeably.
package protocol EnabledTraitConvertible: Equatable {
    var asEnabledTrait: EnabledTrait { get }
}

// MARK: String + EnabledTraitConvertible

extension String: EnabledTraitConvertible {
    package var asEnabledTrait: EnabledTrait {
        .init(stringLiteral: self)
    }
}

// MARK: - Collection + EnabledTrait

extension Collection where Element == EnabledTrait {
    public var names: Set<String> {
        Set<String>(self.map(\.name))
    }

    public func contains(_ trait: String) -> Bool {
        return self.map(\.name).contains(trait)
    }

    public func contains(_ trait: Element) -> Bool {
        return self.contains(trait.description)
    }

    public func joined(separator: String = "") -> String {
        names.joined(separator: separator)
    }
}


// MARK: - IdentifiableSet + EnabledTrait

extension IdentifiableSet where Element == EnabledTrait {
    private mutating func insertTrait(_ member: Element) {
        if let oldElement = self.remove(member), let newElement = oldElement.unify(member) {
            insert(newElement)
        } else {
            insert(member)
        }
    }

    public func union(_ other: IdentifiableSet<Element>) -> IdentifiableSet<Element> {
        var updatedContents = self
        for element in other {
            updatedContents.insertTrait(element)
        }
        return updatedContents
    }

    public func union<C: Collection>(_ other: C) -> IdentifiableSet<Element> where C.Element == Element {
        if let other = other as? IdentifiableSet<Element> {
            return self.union(other)
        } else {
            return self.union(IdentifiableSet(other.map({ $0 })))
        }
    }
}

