/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
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

    public init(name: String, type: ProductType, targets: [Target], testManifest: AbsolutePath? = nil) throws {
        guard !targets.isEmpty else {
            throw InternalError("Targets cannot be empty")
        }
        if type == .executable {
            guard targets.filter({ $0.type == .executable }).count == 1 else {
                throw InternalError("Executable products should have exactly one executable target.")
            }
        }
        if testManifest != nil {
            guard type == .test else {
                throw InternalError("Test manifest should only be set on test products")
            }
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
/// Any product which matches the filter will be used for dependency resolution, whereas unrequested products will be ignored.
///
/// Requested products need not actually exist in the package. Under certain circumstances, the resolver may request names whose package of origin are unknown. The intended package will recognize and fulfill the request; packages that do not know what it is will simply ignore it.
public enum ProductFilter: Codable, Equatable, Hashable {

    /// All products, targets, and tests are requested.
    ///
    /// This is used for root packages.
    case everything

    // FIXME: If command plugins become explicit in the manifest, or are extricated from the main graph, `includeCommands` should be removed.
    /// A set of specific products requested by one or more client packages.
    ///
    /// `includeCommands` is used by first‐level dependencies to also request any command plugins, regardless of whether they are referenced anywhere.
    case specific(Set<String>, includeCommands: Bool = false)

    /// No products, targets, or tests are requested.
    public static var nothing: ProductFilter { .specific([]) }

    public func union(_ other: ProductFilter) -> ProductFilter {
        switch self {
        case .everything:
            return .everything
        case .specific(let set, let includeCommands):
            switch other {
            case .everything:
                return .everything
            case .specific(let otherSet, let otherIncludeCommands):
                return .specific(
                    set.union(otherSet),
                    includeCommands: includeCommands || otherIncludeCommands
                )
            }
        }
    }

    public mutating func formUnion(_ other: ProductFilter) {
        self = self.union(other)
    }

    public func contains(_ product: String, isCommandPlugin: (String) -> Bool) -> Bool {
        switch self {
        case .everything:
            return true
        case .specific(let set, let includeCommands):
            return set.contains(product)
            || (includeCommands && isCommandPlugin(product))
        }
    }

    internal func includingImplicitCommands() -> ProductFilter {
        switch self {
        case .everything:
            return self
        case .specific(let set, _):
            return .specific(set, includeCommands: true)
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
        case .specific(let set, let includeCommands):
            return "[\(set.sorted().joined(separator: ", "))\(includeCommands ? " (including commands)" : "")]"
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
