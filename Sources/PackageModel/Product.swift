/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility

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

    /// The path to linux main file.
    public let linuxMain: AbsolutePath?

    /// The suffix for REPL product name.
    public static let replProductSuffix: String = "__REPL"

    public init(name: String, type: ProductType, targets: [Target], linuxMain: AbsolutePath? = nil) {
        precondition(!targets.isEmpty)
        if type == .executable {
            assert(targets.filter({ $0.type == .executable }).count == 1,
                   "Executable products should have exactly one executable target.")
        }
        if linuxMain != nil {
            assert(type == .test, "Linux main should only be set on test products")
        }
        self.name = name
        self.type = type
        self._targets = .init(wrappedValue: targets)
        self.linuxMain = linuxMain 
    }
}

/// The type of product.
public enum ProductType: Equatable {

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

    /// A test product.
    case test
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
        }
    }
}

// MARK: - Codable

extension ProductType: Codable {
    private enum CodingKeys: String, CodingKey {
        case library, executable, test
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .library(a1):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .library)
            try unkeyedContainer.encode(a1)
        case .executable:
            try container.encodeNil(forKey: .executable)
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
        }
    }
}
