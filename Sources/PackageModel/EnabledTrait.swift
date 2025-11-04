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
/// This struct implicitly omits adding `default` traits to its storage, and returns `nil` if it
/// there is no existing entry for a given package, since if there are no explicitly enabled traits
/// set by anything else a package will then default to its `default` traits, if they exist.
///
/// ## Union Behavior
/// When setting traits via the subscript setter (e.g., `map[packageId] = ["trait1", "trait2"]`),
/// the new traits are **unified** with any existing traits for that package, rather than
/// replacing them. This means multiple assignments to the same package will accumulate
/// all traits into a union. If the same trait name is set multiple times with different setters, the
/// setters are merged together.
///
/// Example:
/// ```swift
/// var traits = EnabledTraitsMap()
/// traits[packageId] = ["Apple", "Banana"]
/// traits[packageId] = ["Coffee", "Chocolate"]
///
/// // traits[packageId] now contains all four traits:
/// print(traits[packageId])
/// // Output: ["Apple", "Banana", "Coffee", "Chocolate"]
/// ```
///
/// ## Disablers
/// When a package or trait configuration explicitly sets an empty trait set (`[]`) for another package,
/// this is tracked as a "disabler" to record the intent to disable default traits. Disablers coexist
/// with the unified trait system—a package can have both recorded disablers AND explicitly enabled
/// traits. This allows the system to distinguish between "no traits specified" versus "default traits
/// explicitly disabled but other traits may be enabled by different parents."
///
/// Only packages (via `Setter.package`) and trait configurations (via `Setter.traitConfiguration`)
/// can disable default traits. Traits themselves cannot disable other packages' default traits.
///
/// Example:
/// ```swift
/// var traits = EnabledTraitsMap()
/// let dependencyId = PackageIdentity(stringLiteral: "MyDependency")
/// let parent1 = PackageIdentity(stringLiteral: "Parent1")
/// let parent2 = PackageIdentity(stringLiteral: "Parent2")
///
/// // Parent1 explicitly disables default traits
/// traits[dependencyId] = EnabledTraits([], setBy: .package(.init(identity: parent1)))
///
/// // Parent2 enables specific traits for the same dependency
/// traits[dependencyId] = EnabledTraits(["MyTrait"], setBy: .package(.init(identity: parent2)))
///
/// // Query disablers to see who disabled defaults
/// print(traits[disablersFor: dependencyId])  // Contains .package(Parent1)
///
/// // The dependency has "MyTrait" trait enabled (unified from Parent2)
/// print(traits[dependencyId])  // Output: ["MyTrait"]
/// ```
public struct EnabledTraitsMap {
    public typealias Key = PackageIdentity
    public typealias Value = EnabledTraits

    /// Storage for explicitly enabled traits per package. Omits packages with only the "default" trait.
    private var storage: ThreadSafeKeyValueStore<PackageIdentity, EnabledTraits> = .init()

    /// Tracks setters that explicitly disabled default traits (via []) for each package.
    private var _disablers: ThreadSafeKeyValueStore<PackageIdentity, Set<EnabledTrait.Setter>> = .init()

    /// Tracks setters that requested default traits for each package.
    /// This is used when a parent doesn't specify traits, meaning it wants the dependency to use its defaults.
    private var _defaultSetters: ThreadSafeKeyValueStore<PackageIdentity, Set<EnabledTrait.Setter>> = .init()

    public init() { }

    public subscript(key: String) -> EnabledTraits {
        get { self[PackageIdentity(key)] }
        set { self[PackageIdentity(key)] = newValue }
    }

    public subscript(key: PackageIdentity) -> EnabledTraits {
        get { storage[key] ?? ["default"] }
        set {
            // Omit adding "default" explicitly, since the map returns "default"
            // if there are no explicit traits enabled. This will allow us to check
            // for nil entries in the stored dictionary, which tells us whether
            // traits have been explicitly enabled or not.
            //
            // However, if "default" is explicitly set by a parent (has setters),
            // track it in the `defaultSetters` property.
            guard !(newValue == .defaults && !newValue.isExplicitlySetDefault) else {
                return
            }

            // Track setter that disabled all default traits;
            // continue to union existing enabled traits.
            if newValue.isEmpty, let disabler = newValue.disabledBy {
                if !self._disablers.contains(key) {
                    _disablers[key] = []
                }
                _disablers[key]?.insert(disabler)
            }

            // Check if this is an explicitly-set "default" trait (parent wants defaults enabled)
            if newValue.isExplicitlySetDefault {
                // Track that this parent wants default traits, but don't store the sentinel "default"
                // The actual default traits will be resolved when the dependency's manifest is loaded
                if let defaultSetter = newValue.first?.setters.first {
                    if !self._defaultSetters.contains(key) {
                        _defaultSetters[key] = []
                    }
                    _defaultSetters[key]?.insert(defaultSetter)
                }

                // If explicitly disabled default traits prior, then
                // reset this in storage and assure we can still fetch defaults.
                // We will still track whenever default traits were disabled by
                // keeping the _disablers map as it was.
                if self.storage[key] == [] {
                    self.storage[key] = nil
                }
                return
            }

            // If there are no explictly enabled traits added yet, then create entry.
            if storage[key] == nil {
                storage[key] = newValue
            } else {
                // Combine the existing set of enabled traits with the newValue.
                storage[key]?.formUnion(newValue)
            }
        }
    }

    public subscript(disablersFor key: PackageIdentity) -> Set<EnabledTrait.Setter>? {
        get { self._disablers[key] }
    }

    public subscript(disablersFor key: String) -> Set<EnabledTrait.Setter>? {
        self[disablersFor: .init(key)]
    }

    public subscript(defaultSettersFor key: PackageIdentity) -> Set<EnabledTrait.Setter>? {
        get { self._defaultSetters[key] }
    }

    public subscript(defaultSettersFor key: String) -> Set<EnabledTrait.Setter>? {
        self[defaultSettersFor: .init(key)]
    }

    /// Returns a list of traits that were explicitly enabled for a given package.
    public subscript(explicitlyEnabledTraitsFor key: PackageIdentity) -> EnabledTraits? {
        get { storage[key] }
    }

    /// Returns a list of traits that were explicitly enabled for a given package.
    public subscript(explicitlyEnabledTraitsFor key: String) -> EnabledTraits? {
        self[explicitlyEnabledTraitsFor: .init(key)]
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

    public init(_ dictionary: [String: Value]) {
        let mappedDictionary = dictionary.reduce(into: [Key: Value]()) { result, element in
            result[PackageIdentity(element.key)] = element.value
        }
        self.storage = .init(mappedDictionary)
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

    /// Returns true if this trait is the "default" trait.
    public var isDefault: Bool {
        name == "default"
    }

    /// Returns true if this trait was enabled by the "default" trait (via `Setter.trait("default")`).
    /// This is distinct from `isDefault`, which checks if this trait's name is "default".
    public var isSetByDefault: Bool {
        self.setters.contains(where: { $0 == .default })
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
                "package \(parent.description)"
            case .trait(let trait):
                "trait \(trait)"
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

        public var parentTrait: String? {
            switch self {
            case .trait(let trait):
                return trait
            case .traitConfiguration, .package:
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
///
/// ## Disabling All Traits
/// An `EnabledTraits` instance can represent a "disabled" state when created with an empty collection
/// and a `Setter`. In this case, the `disabledBy` property returns the setter that disabled default traits,
/// allowing callers to track which parent package or configuration explicitly disabled default traits for a package.
public struct EnabledTraits: Hashable {
    public typealias Element = EnabledTrait
    public typealias Index = IdentifiableSet<Element>.Index

    /// Storage of enabled traits.
    private var _traits: IdentifiableSet<EnabledTrait> = []

    /// This should only ever be set in the case where a parent
    /// disables all traits, and an empty set of traits is passed.
    private var _disableAllTraitsSetter: EnabledTrait.Setter? = nil

    /// Returns the setter that disabled all traits for a package, if any.
    /// This value is set when `EnabledTraits` is initialized with an empty collection,
    /// indicating that a parent explicitly disabled all traits rather than leaving them
    /// unset.
    public var disabledBy: EnabledTrait.Setter? {
        _disableAllTraitsSetter
    }

    public var areDefaultsEnabled: Bool {
        return !_traits.filter(\.isDefault).isEmpty || !_traits.filter(\.isSetByDefault).isEmpty
    }

    /// Returns true if this represents an explicitly-set "default" trait (with setters),
    /// as opposed to the sentinel `.defaults` value (no setters).
    /// This is used to distinguish when a parent explicitly wants default traits enabled
    /// versus when no traits have been specified at all.
    public var isExplicitlySetDefault: Bool {
        // Check if this equals .defaults (only contains "default" trait) AND has explicit setters
        return self == .defaults && _traits.contains(where: { !$0.setters.isEmpty })
    }

    public static var defaults: EnabledTraits {
        ["default"]
    }

    private init(_ disabler: EnabledTrait.Setter) {
        self._disableAllTraitsSetter = disabler
    }

    public init<C: Collection>(_ traits: C, setBy setter: EnabledTrait.Setter) where C.Element == String {
        guard !traits.isEmpty else {
            self.init(setter)
            return
        }
        let enabledTraits = traits.map({ EnabledTrait(name: $0, setBy: setter) })
        self.init(enabledTraits)
    }

    public init(_ enabledTraits: EnabledTraits) {
        self._traits = enabledTraits._traits
    }

    private init<C: Collection>(_ traits: C) where C.Element == EnabledTrait {
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

    public func union<C: Collection>(_ other: C) -> EnabledTraits where C.Element == Self.Element {
        let unionedTraits = _traits.union(other)
        return EnabledTraits(unionedTraits)
    }

    public mutating func formUnion(_ other: EnabledTraits) {
        self._traits = self.union(other)._traits
    }

    public mutating func formUnion<C: Collection>(_ other: C) where C.Element == Self.Element {
        self.formUnion(.init(other))
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

    package func union<C: Collection>(_ other: C) -> IdentifiableSet<Element> where C.Element == Element {
        var updatedContents = self
        for element in other {
            updatedContents.insertTrait(element)
        }
        return updatedContents
    }
}

