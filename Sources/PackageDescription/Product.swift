//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2018-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// The object that defines a package product.
///
/// A package product defines an externally visible build artifact that's
/// available to clients of a package. Swift Package Manager assembles the product from the
/// build artifacts of one or more of the package's targets. A package product
/// can be one of three types:
///
/// - term Library: Use a _library product_ to vend library targets. This makes
/// a target's public APIs available to clients that integrate the Swift
/// package.
/// - term Executable: Use an _executable product_ to vend an
/// executable target. Use this only if you want to make the executable
/// available to clients.
/// - term Plugin: Use a _plugin product_ to vend plugin targets. This makes
/// the plugin available to clients that integrate the Swift package.
///
/// The following example shows a package manifest for a library called “Paper”
/// that defines multiple products:
///
/// ```swift
/// let package = Package(
///     name: "Paper",
///     products: [
///         .executable(name: "tool", targets: ["tool"]),
///         .library(name: "Paper", targets: ["Paper"]),
///         .library(name: "PaperStatic", type: .static, targets: ["Paper"]),
///         .library(name: "PaperDynamic", type: .dynamic, targets: ["Paper"]),
///     ],
///     dependencies: [
///         .package(url: "http://example.com.com/ExamplePackage/ExamplePackage", from: "1.2.3"),
///         .package(url: "http://some/other/lib", .exact("1.2.3")),
///     ],
///     targets: [
///         .executableTarget(
///             name: "tool",
///             dependencies: [
///                 "Paper",
///                 "ExamplePackage"
///             ]),
///         .target(
///             name: "Paper",
///             dependencies: [
///                 "Basic",
///                 .target(name: "Utility"),
///                 .product(name: "AnotherExamplePackage"),
///             ])
///     ]
/// )
/// ```
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

        /// Encodes this executable product type into the given encoder.
        ///
        /// This function throws an error if any values are invalid for the
        /// given encoder's format.
        ///
        /// - Note: Do not call this function directly. It is public to satisfy conformance to Codable, but it is only for use by internal Swift Package Manager processes.
        ///
        /// - Parameter encoder: The encoder to write data to.
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
        /// If the type is unspecified, the Swift Package Manager automatically chooses a type
        /// based on the client's preference.
        public let type: LibraryType?

        init(name: String, type: LibraryType? = nil, targets: [String]) {
            self.type = type
            self.targets = targets
            super.init(name: name)
        }

        /// Encodes this value into the given encoder.
        ///
        /// If the value fails to encode anything, `encoder` will encode an
        /// empty keyed container in its place.
        ///
        /// This function throws an error if any values are invalid for the
        /// given encoder's format.
        ///
        /// - Parameter encoder: The encoder to write data to.
        public override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            var productContainer = encoder.container(keyedBy: ProductCodingKeys.self)
            try productContainer.encode("library", forKey: .type)
            var libraryContainer = encoder.container(keyedBy: LibraryCodingKeys.self)
            try libraryContainer.encode(type, forKey: .type)
            try libraryContainer.encode(targets, forKey: .targets)
        }
    }

    /// The plugin product of a Swift package.
    public final class Plugin: Product {
        private enum PluginCodingKeys: CodingKey {
            case targets
        }

        /// The name of the plugin target to vend as a product.
        public let targets: [String]

        init(name: String, targets: [String]) {
            self.targets = targets
            super.init(name: name)
        }

        public override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            var productContainer = encoder.container(keyedBy: ProductCodingKeys.self)
            try productContainer.encode("plugin", forKey: .type)
            var pluginContainer = encoder.container(keyedBy: PluginCodingKeys.self)
            try pluginContainer.encode(targets, forKey: .targets)
        }
    }

    /// Creates a library product to allow clients that declare a dependency on
    /// this package to use the package's functionality.
    ///
    /// A library's product can be either statically or dynamically linked. It's recommended
    /// that you don't explicity declare the type of library, so Swift Package Manager can
    /// choose between static or dynamic linking based on the preference of the
    /// package's consumer.
    ///
    /// - Parameters:
    ///   - name: The name of the library product.
    ///   - type: The optional type of the library that's used to determine how to
    ///     link to the library. Leave this parameter so
    ///     Swift Package Manager can choose between static or dynamic linking (recommended). If you
    ///     don't support both linkage types, use
    ///     ``Product/Library/LibraryType/static`` or
    ///     ``Product/Library/LibraryType/dynamic`` for this parameter.
    ///
    ///  - targets: The targets that are bundled into a library product.
    ///
    /// - Returns: A `Product` instance.
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
    ///   - name: The name of the executable product.
    ///   - targets: The targets to bundle into an executable product.
    /// - Returns: A `Product` instance.
public static func executable(
        name: String,
        targets: [String]
    ) -> Product {
        return Executable(name: name, targets: targets)
    }

    /// Defines a product that vends a package plugin target for use by clients of the package.
    ///
    /// It is not necessary to define a product for a plugin that
    /// is only used within the same package where you define it. All the targets
    /// listed must be plugin targets in the same package as the product. Swift Package Manager
    /// will apply them to any client targets of the product in the order
    /// they are listed.
    /// - Parameters:
    ///   - name: The name of the plugin product.
    ///   - targets: The plugin targets to vend as a product.
    /// - Returns: A `Product` instance.
@available(_PackageDescription, introduced: 5.5)
    public static func plugin(
        name: String,
        targets: [String]
    ) -> Product {
        return Plugin(name: name, targets: targets)
    }

    /// Encodes this value into the given encoder.
    ///
    /// If the value fails to encode anything, `encoder` will encode an empty
    /// keyed container in its place.
    ///
    /// This function throws an error if any values are invalid for the given
    /// encoder's format.
    ///
    /// - Parameter encoder: The encoder to write data to.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ProductCodingKeys.self)
        try container.encode(name, forKey: .name)
    }
}
