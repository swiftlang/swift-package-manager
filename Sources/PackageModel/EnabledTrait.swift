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

/// A wrapper struct for a dictionary that stores the transitively enabled traits for each package.
/// This struct implicitly omits adding `default` traits to its storage, and returns `nil` if it there is no existing entry for
/// a given package, since if there are no explicitly enabled traits set by anything else a package will then default to its `default` traits,
/// if they exist.
public struct EnabledTraitsMap: ExpressibleByDictionaryLiteral {
    public typealias Key = PackageIdentity
    public typealias Value = EnabledTraits

    var storage: [PackageIdentity: EnabledTraits] = [:]

    public init() { }

    public init(dictionaryLiteral elements: (Key, Value)...) {
        for (key, value) in elements {
            storage[key] = value
        }
    }

    public init(_ dictionary: [Key: Value]) {
        self.storage = dictionary
    }

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

    public subscript(explicitlyEnabledTraitsFor key: PackageIdentity) -> EnabledTraits? {
        get { storage[key] }
    }

    public var dictionaryLiteral: [PackageIdentity: EnabledTraits] {
        return storage
    }
}

// MARK: - EnabledTrait

/// A structure representing a trait that is enabled. The package in which this is enabled on is identified in
/// the EnabledTraitsMap.
///
/// An enabled trait is a trait that is either explicitly enabled by a user-passed trait configuration from the command line,
/// a parent package that has defined enabled traits for its dependency package(s), or by another trait (including the default case).
///
/// An EnabledTrait is differentiated by its `name`, and all other data stored in this struct is treated as metadata for
/// convenience. When unifying two `EnabledTrait`s, it will combine the list of setters (`setBy`) if the `name`s match.
///
public struct EnabledTrait: Identifiable, CustomStringConvertible, ExpressibleByStringLiteral, Comparable {
    // Convenience typealias for a list of `Setter`
    public typealias Setters = Set<Setter>

    // The identifier for the trait.
    public var id: String { name }

    // The name of the trait.
    public let name: String

    // The list of setters who have enabled this trait.
    public var setters: Setters = []

    /// An enumeration that describes where a given trait was enabled.
    public enum Setter: Hashable, CustomStringConvertible {
//        case `default`
        case traitConfiguration
        case package(Manifest.PackageIdentifier)
        case trait(String)

        public var description: String {
            switch self {
//            case .default:
//                "default"
            case .traitConfiguration:
                "custom trait configuration."
            case .package(let parent):
                parent.description
            case .trait(let trait):
                trait
            }
        }

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

    public init(name: String, setBy: Setter) {
        self.name = name
        self.setters = [setBy]
    }

    public init(name: String, setBy: [Setter]) {
        self.name = name
        self.setters = Set(setBy)
    }

    public var parentPackages: [Manifest.PackageIdentifier] {
        setters.compactMap(\.parentPackage)
    }

    public var isDefault: Bool {
        name == "default"
    }

    public func unify(_ otherTrait: EnabledTrait) -> EnabledTrait? {
        guard self.name == otherTrait.name else {
            return nil
        }

        var updatedTrait = self
        updatedTrait.setters = setters.union(otherTrait.setters)
        return updatedTrait
    }

    // MARK: - CustomStringConvertible
    public var description: String {
        name
    }

    // MARK: - ExpressibleByStringLiteral
    public init(stringLiteral value: String) {
        self.name = value
    }

    // MARK: - Equatable

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

    // MARK: - Comparable

    public static func <(lhs: EnabledTrait, rhs: EnabledTrait) -> Bool {
        return lhs.name < rhs.name
    }
}

// MARK: - EnabledTraits

/// This struct acts as a wrapper for a set of `EnabledTrait` to handle special cases.
public struct EnabledTraits: ExpressibleByArrayLiteral, Collection, Hashable {
    public typealias Element = EnabledTrait
    public typealias Index = IdentifiableSet<Element>.Index

    private var _traits: IdentifiableSet<EnabledTrait> = []

    public static var defaults: EnabledTraits {
        ["default"]
    }

    public init(arrayLiteral elements: Element...) {
        for element in elements {
            _traits.insert(element)
        }
    }

    public init<C: Collection>(_ traits: C, setBy origin: EnabledTrait.Setter) where C.Element == String {
        let enabledTraits = traits.map({ EnabledTrait(name: $0, setBy: origin) })
        self.init(enabledTraits)
    }

    public init<C: Collection>(_ traits: C) where C.Element == EnabledTrait {
        self._traits = IdentifiableSet(traits)
    }

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

    public mutating func formUnion(_ other: EnabledTraits) {
        self._traits = self.union(other)._traits
    }

    public func flatMap(_ transform: (Self.Element) throws -> EnabledTraits) rethrows -> EnabledTraits {
        let transformedTraits = try _traits.flatMap(transform)
        return EnabledTraits(transformedTraits)
    }

    public func map(_ transform: (Self.Element) throws -> Self.Element) rethrows -> EnabledTraits {
        let transformedTraits = try _traits.map(transform)
        return EnabledTraits(transformedTraits)
    }

    public func union(_ other: EnabledTraits) -> EnabledTraits {
        let unionedTraits = _traits.union(other)
        return EnabledTraits(unionedTraits)
    }

    public mutating func remove(_ member: Element) -> Element? {
        return _traits.remove(member)
    }

    public mutating func insert(_ newMember: Element) {
        _traits.insert(newMember)
    }

    public func contains(_ member: Element) -> Bool {
        return _traits.contains(member)
    }

    public static func ==<C: Collection>(_ lhs: EnabledTraits, _ rhs: C) -> Bool where C.Element == Element {
        lhs._traits.names == rhs.names
    }

    public static func ==<C: Collection>(_ lhs: C, _ rhs: EnabledTraits) -> Bool where C.Element == Element {
        lhs.names == rhs._traits.names
    }

    public static func ==(_ lhs: EnabledTraits, _ rhs: EnabledTraits) -> Bool {
        lhs._traits.names == rhs._traits.names
    }
}

extension Collection where Element == EnabledTrait {
    public func contains(_ trait: String) -> Bool {
        return self.map(\.name).contains(trait)
    }

    public func contains(_ trait: Element) -> Bool {
        return self.contains(trait.description)
    }

    public var names: Set<String> {
        Set<String>(self.map(\.name))
    }

    public func joined(separator: String = "") -> String {
        names.joined(separator: separator)
    }
}

extension IdentifiableSet where Element == EnabledTrait {
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

    private mutating func insertTrait(_ member: Element) {
        if let oldElement = self.remove(member), let newElement = oldElement.unify(member) {
            insert(newElement)
        } else {
            insert(member)
        }
    }
}

