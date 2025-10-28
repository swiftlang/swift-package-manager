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

/// A wrapper for a dictionary that stores the transitively enabled traits for each package.
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

    public subscript(key: PackageIdentity/*, setBy: EnabledTrait.Origin = .traitConfiguration*/) -> EnabledTraits {
        get { storage[key] ?? ["default"] }
        set {
            // Omit adding "default" explicitly, since the map returns "default"
            // if there is no explicit traits declared. This will allow us to check
            // for nil entries in the stored dictionary, which tells us whether
            // traits have been explicitly declared.
            print("adding \(newValue) traits to \(key.description)")
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

public struct EnabledTrait: Hashable, CustomStringConvertible, ExpressibleByStringLiteral, Comparable {
    public let name: String
    public var setBy: Set<Origin> = []

    public enum Origin: Hashable, CustomStringConvertible {
        case `default`
        case traitConfiguration
        case package(Manifest.PackageIdentifier)
        case trait(String)

        public var description: String {
            switch self {
            case .default:
                "default"
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
            case .traitConfiguration, .trait, .default:
                return nil
            }
        }
    }

    public init(name: String, setBy: Origin) {
        self.name = name
        self.setBy = [setBy]
    }

    public var parentPackages: [Manifest.PackageIdentifier] {
        setBy.compactMap(\.parentPackage)
    }

//    public mutating func formUnion(_ otherOrigin: Set<Origin>) {
//        self.setBy.formUnion(otherOrigin)
//    }

    public func union(_ otherTrait: EnabledTrait) -> EnabledTrait? {
        guard self.name == otherTrait.name else {
            return nil
        }

        var updatedTrait = self
        updatedTrait.setBy = setBy.union(otherTrait.setBy)
        return updatedTrait
    }

    // Static helper method to create Set<EnabledTrait> from a Collection of String.
    public static func createSet<C: Collection>(
        from traits: C,
        enabledBy origin: EnabledTrait.Origin
    ) -> EnabledTraits where C.Element == String {
        .init(Set(traits.map({ EnabledTrait(name: $0, setBy: origin)})))
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
        lhs.name == rhs.name
    }

    public static func ==(lhs: EnabledTrait, rhs: String) -> Bool {
        lhs.name == rhs
    }

    public static func ==(lhs: String, rhs: EnabledTrait) -> Bool {
        lhs == rhs.name
    }

    // MARK: - Comparable

    public static func <(lhs: EnabledTrait, rhs: EnabledTrait) -> Bool {
        return lhs.name < rhs.name
    }
}

// A wrapper struct for a set of `EnabledTrait` to handle special cases.
public struct EnabledTraits: ExpressibleByArrayLiteral, Collection, Hashable {
    public typealias Element = EnabledTrait
    public typealias Index = Set<Element>.Index

    private var _traits: Set<EnabledTrait> = []

    public init(arrayLiteral elements: EnabledTrait...) {
        for element in elements {
            _traits.insert(element)
        }
    }

    public init<C: Collection>(_ traits: C, setBy origin: EnabledTrait.Origin) where C.Element == String {
        let traits = Set(traits.map({ EnabledTrait(name: $0, setBy: origin) }))
        self.init(traits)
    }

    public init<C: Collection>(_ traits: C) where C.Element == EnabledTrait {
        self._traits = Set(traits)
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
        _traits = Set(
            _traits.compactMap { trait in
                if let otherTrait = other.first(where: { $0 == trait }) {
                    return trait.union(otherTrait)
                } else {
                    return trait
                }
            }
        )
    }

    public func flatMap(_ transform: (Self.Element) throws -> Self) rethrows -> Self {
        let transformedTraits = try _traits.flatMap(transform)
        return EnabledTraits(transformedTraits)
    }

    public func union(_ other: EnabledTraits) -> EnabledTraits {
        print("enabled traits in self: \(_traits)")
        print("to union with: \(other)")
        let unionedTraits = _traits.union(other)
        print("after union: \(unionedTraits)")
        return EnabledTraits(unionedTraits)
    }

    public mutating func remove(_ member: Element) -> Element? {
        return _traits.remove(member)
    }

    public mutating func insert(_ newMember: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        return _traits.insert(newMember)
    }

    public func contains(_ member: Element) -> Bool {
        return _traits.contains(member)
    }
}

extension Collection where Element == EnabledTrait {
    public func contains(_ trait: String) -> Bool {
        self.map(\.name).contains(trait)
    }

    public var names: Set<String> {
        Set<String>(self.map(\.name))
    }

    public func joined(separator: String = "") -> String {
        names.joined(separator: separator)
    }
}

