/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

import struct TSCUtility.PolymorphicCodableArray

public class Product: Codable {
    /// The name of the product.
    public let name: String

    /// The type of product to create.
    public let type: ProductType

    /// The list of targets to combine to form the product.
    ///
    /// This is never empty, and is only the targets which are required to be in
    /// the product, but not necessarily their transitive dependencies.
    @PolymorphicCodableArray
    public var targets: [Target]

    /// The path to test manifest file.
    public let testManifest: AbsolutePath?

    /// The suffix for REPL product name.
    public static let replProductSuffix: String = "__REPL"

    public init(name: String, type: ProductType, targets: [Target], testManifest: AbsolutePath? = nil) {
        precondition(!targets.isEmpty)
        if type == .executable {
            assert(targets.filter({ $0.type == .executable }).count == 1,
                   "Executable products should have exactly one executable target.")
        }
        if testManifest != nil {
            assert(type == .test, "Test manifest should only be set on test products")
        }
        self.name = name
        self.type = type
        self._targets = .init(wrappedValue: targets)
        self.testManifest = testManifest
    }
}

extension Product: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public static func == (lhs: Product, rhs: Product) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}

/// The type of product.
public enum ProductType: Equatable, Hashable {

    /// The type of library.
    public enum LibraryType: String, Codable {

        /// Static library.
        case `static`

        /// Dynamic library.
        case `dynamic`

        /// The type of library is unspecified and should be decided by package manager.
        case automatic
    }

    /// A library product.
    case library(LibraryType)

    /// An executable product.
    case executable

    /// An executable code snippet.
    case snippet

    /// An plugin product.
    case plugin

    /// A test product.
    case test

    public var isLibrary: Bool {
        guard case .library = self else { return false }
        return true
    }
}


/// The products requested of a package.
///
/// Any product which matches the filter will be used for dependency resolution, whereas unrequested products will be ingored.
///
/// Requested products need not actually exist in the package. Under certain circumstances, the resolver may request names whose package of origin are unknown. The intended package will recognize and fullfill the request; packages that do not know what it is will simply ignore it.
public enum ProductFilter: Equatable, Hashable {

    /// All products, targets, and tests are requested.
    ///
    /// This is used for root packages.
    case everything

    /// A set of specific products requested by one or more client packages.
    case specific(Set<String>)

    /// No products, targets, or tests are requested.
    public static var nothing: ProductFilter { .specific([]) }

    public func union(_ other: ProductFilter) -> ProductFilter {
        switch self {
        case .everything:
            return .everything
        case .specific(let set):
            switch other {
            case .everything:
                return .everything
            case .specific(let otherSet):
                return .specific(set.union(otherSet))
            }
        }
    }

    public mutating func formUnion(_ other: ProductFilter) {
        self = self.union(other)
    }

    public func contains(_ product: String) -> Bool {
        switch self {
        case .everything:
            return true
        case .specific(let set):
            return set.contains(product)
        }
    }

    public func merge(_ other: ProductFilter) -> ProductFilter {
        switch (self, other) {
        case (.everything, _):
            return .everything
        case (_, .everything):
            return .everything
        case (.specific(let mine), .specific(let other)):
            return .specific(mine.union(other))
        }
    }
}


// MARK: - CustomStringConvertible

extension Product: CustomStringConvertible {
    public var description: String {
        return "<Product: \(name)>"
    }
}

extension ProductType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .executable:
            return "executable"
        case .snippet:
            return "snippet"
        case .test:
            return "test"
        case .library(let type):
            switch type {
            case .automatic:
                return "automatic"
            case .dynamic:
                return "dynamic"
            case .static:
                return "static"
            }
        case .plugin:
            return "plugin"
        }
    }
}

extension ProductFilter: CustomStringConvertible {
    public var description: String {
        switch self {
        case .everything:
            return "[everything]"
        case .specific(let set):
            return "[\(set.sorted().joined(separator: ", "))]"
        }
    }
}

// MARK: - Codable

extension ProductType: Codable {
    private enum CodingKeys: String, CodingKey {
        case library, executable, snippet, plugin, test
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .library(a1):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .library)
            try unkeyedContainer.encode(a1)
        case .executable:
            try container.encodeNil(forKey: .executable)
        case .snippet:
            try container.encodeNil(forKey: .snippet)
        case .plugin:
            try container.encodeNil(forKey: .plugin)
        case .test:
            try container.encodeNil(forKey: .test)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = values.allKeys.first(where: values.contains) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
        }
        switch key {
        case .library:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let a1 = try unkeyedValues.decode(ProductType.LibraryType.self)
            self = .library(a1)
        case .test:
            self = .test
        case .executable:
            self = .executable
        case .snippet:
            self = .snippet
        case .plugin:
            self = .plugin
        }
    }
}

extension ProductFilter: Codable {
    public func encode(to encoder: Encoder) throws {
        let optionalSet: Set<String>?
        switch self {
        case .everything:
            optionalSet = nil
        case .specific(let set):
            optionalSet = set
        }
        var container = encoder.singleValueContainer()
        try container.encode(optionalSet?.sorted())
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .everything
        } else {
            self = .specific(Set(try container.decode([String].self)))
        }
    }
}
