/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Defines a product in the package.
public class Product: Encodable {
    private enum ProductCodingKeys: String, CodingKey {
        case name
        case type = "product_type"
    }

    /// The name of the product.
    public let name: String

    init(name: String) {
        self.name = name
    }

    /// Represents an executable product.
    public final class Executable: Product {
        private enum ExecutableCodingKeys: CodingKey {
            case targets
        }

        /// The names of the targets in this product.
        public let targets: [String]

        init(name: String, targets: [String]) {
            self.targets = targets
            super.init(name: name)
        }

        public override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            var productContainer = encoder.container(keyedBy: ProductCodingKeys.self)
            try productContainer.encode("executable", forKey: .type)
            var executableContainer = encoder.container(keyedBy: ExecutableCodingKeys.self)
            try executableContainer.encode(targets, forKey: .targets)
        }
    }

    /// Represents a library product.
    public final class Library: Product {
        private enum LibraryCodingKeys: CodingKey {
            case type
            case targets
        }

        /// The type of library product.
        public enum LibraryType: String, Encodable {
            case `static`
            case `dynamic`
        }

        /// The names of the targets in this product.
        public let targets: [String]

        /// The type of the library.
        ///
        /// If the type is unspecified, package manager will automatically choose a type.
        public let type: LibraryType?

        init(name: String, type: LibraryType? = nil, targets: [String]) {
            self.type = type
            self.targets = targets
            super.init(name: name)
        }

        public override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            var productContainer = encoder.container(keyedBy: ProductCodingKeys.self)
            try productContainer.encode("library", forKey: .type)
            var libraryContainer = encoder.container(keyedBy: LibraryCodingKeys.self)
            try libraryContainer.encode(type, forKey: .type)
            try libraryContainer.encode(targets, forKey: .targets)
        }
    }

    /// Create a library product.
    public static func library(
        name: String,
        type: Library.LibraryType? = nil,
        targets: [String]
    ) -> Product {
        return Library(name: name, type: type, targets: targets)
    }

    /// Create an executable product.
    public static func executable(
        name: String,
        targets: [String]
    ) -> Product {
        return Executable(name: name, targets: targets)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ProductCodingKeys.self)
        try container.encode(name, forKey: .name)
    }
}
