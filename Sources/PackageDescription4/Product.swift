/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Defines a package product.
///
/// A package product defines an externally visible build artifact that is
/// available to clients of a package. The product is assembled from the build
/// artifacts of one or more of the package's targets.
///
/// A package product can be one of two types:
///
/// 1. Library
///
///     A library product is used to vend library targets containing the public
///     APIs that will be available to clients.
///
/// 2. Executable
///
///     An executable product is used to vend an executable target. This should
///     only be used if the executable needs to be made available to clients.
///
/// The following example shows a package manifest for a library called "Paper"
/// that defines multiple products:
///
///     let package = Package(
///         name: "Paper",
///         products: [
///             .executable(name: "tool", targets: ["tool"]),
///             .library(name: "Paper", targets: ["Paper"]),
///             .library(name: "PaperStatic", type: .static, targets: ["Paper"]),
///             .library(name: "PaperDynamic", type: .dynamic, targets: ["Paper"]),
///         ],
///         dependencies: [
///             .package(url: "http://example.com.com/ExamplePackage/ExamplePackage", from: "1.2.3"),
///             .package(url: "http://some/other/lib", .exact("1.2.3")),
///         ],
///         targets: [
///             .target(
///                 name: "tool",
///                 dependencies: [
///                     "Paper",
///                     "ExamplePackage"
///                 ]),
///             .target(
///                 name: "Paper",
///                 dependencies: [
///                     "Basic",
///                     .target(name: "Utility"),
///                     .product(name: "AnotherExamplePackage"),
///                 ])
///         ]
///     )
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

    /// Create a library product that can be used by clients that depend on this package.
    ///
    /// A library's product can either be statically or dynamically linked. It
    /// is recommended to not declare the type of library explicitly to let the
    /// Swift Package Manager choose between static or dynamic linking depending
    /// on the consumer of the package.
    ///
    /// - Parameters:
    ///     - name: The name of the library product.
    ///     - type: The optional type of the library that is used to determine how to link to the library.
    ///         Leave this parameter unspecified to let to let the Swift Package Manager choose between static or dynamic linking (recommended).
    ///         If you do not support both linkage types, use `.static` or `.dynamic` for this parameter. 
    ///     - targets: The targets that are bundled into a library product.
    public static func library(
        name: String,
        type: Library.LibraryType? = nil,
        targets: [String]
    ) -> Product {
        return Library(name: name, type: type, targets: targets)
    }

    /// Create an executable product.
    ///
    /// - Parameters:
    ///     - name: The name of the executable product.
    ///     - targets: The targets that are bundled into an executable product.
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
