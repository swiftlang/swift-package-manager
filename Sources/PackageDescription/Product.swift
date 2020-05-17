/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// The object that defines a package product.
///
/// A package product defines an externally visible build artifact that's
/// available to clients of a package. The product is assembled from the build
/// artifacts of one or more of the package's targets.
///
/// A package product can be one of two types:
///
/// 1. **Library**. Use a library product to vend library targets. This makes a target's public APIs
/// available to clients that integrate the Swift package.
/// 2. **Executable**. Use an executable product to vend an executable target.
/// Use this only if you want to make the executable available to clients.
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

    /// The name of the package product.
    public let name: String

    init(name: String) {
        self.name = name
    }

    /// The executable product of a Swift package.
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

    /// The library product of a Swift package.
    public final class Library: Product {
        private enum LibraryCodingKeys: CodingKey {
            case type
            case targets
        }

        /// The different types of a library product.
        public enum LibraryType: String, Encodable {
            /// A statically linked library.
            case `static`
            /// A dynamically linked library.
            case `dynamic`
        }

        /// The names of the targets in this product.
        public let targets: [String]

        /// The type of the library.
        ///
        /// If the type is unspecified, the Swift Package Manager automatically
        /// chooses a type based on the client's preference.
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

    /// Creates a library product to allow clients that declare a dependency on this package
    /// to use the package's functionality.
    ///
    /// A library's product can either be statically or dynamically linked.
    /// If possible, don't declare the type of library explicitly to let 
    /// the Swift Package Manager choose between static or dynamic linking based
    /// on the preference of the package's consumer.
    ///
    /// - Parameters:
    ///     - name: The name of the library product.
    ///     - type: The optional type of the library that's used to determine how to link to the library.
    ///         Leave this parameter unspecified to let to let the Swift Package Manager choose between static or dynamic linking (recommended).
    ///         If you don't support both linkage types, use `.static` or `.dynamic` for this parameter. 
    ///     - targets: The targets that are bundled into a library product.
    public static func library(
        name: String,
        type: Library.LibraryType? = nil,
        targets: [String]
    ) -> Product {
        return Library(name: name, type: type, targets: targets)
    }

    /// Creates an executable package product.
    ///
    /// - Parameters:
    ///     - name: The name of the executable product.
    ///     - targets: The targets to bundle into an executable product.
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
