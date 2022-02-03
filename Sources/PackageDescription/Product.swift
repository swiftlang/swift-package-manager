/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation

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
open class Product: Encodable {
    /// The name of the product.
    public let name: String

    init(name: String) {
        self.name = name
    }

    /// A product that builds an executable binary (such as a command line tool).
    public final class Executable: Product {
        /// The names of the targets that comprise the executable product.
        /// There must be exactly one `executableTarget` among them.
        public let targets: [String]

        init(name: String, targets: [String]) {
            self.targets = targets
            super.init(name: name)
        }

        public override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("executable", forKey: .type)
            try container.encode(targets, forKey: .targets)
        }
    }

    /// A product that builds a library that other targets and products can link against.
    public final class Library: Product {
        /// The names of the targets that comprise the library product.
        public let targets: [String]

        /// The different types of a library product.
        public enum LibraryType: String, Encodable {
            /// A statically linked library (its code will be incorporated
            /// into clients that link to it).
            case `static`
            /// A dynamically linked library (its code will be referenced
            /// by clients that link to it).
            case `dynamic`
        }

        /// The type of library.
        ///
        /// If the type is unspecified, the Swift Package Manager automatically
        /// chooses a type based on how the library is used by the client.
        public let type: LibraryType?

        init(name: String, type: LibraryType? = nil, targets: [String]) {
            self.targets = targets
            self.type = type
            super.init(name: name)
        }

        public override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("library", forKey: .type)
            try container.encode(targets, forKey: .targets)
            let encoder = JSONEncoder()
            struct EncodedLibraryProperties: Encodable {
                public let type: LibraryType?
            }
            let properties = EncodedLibraryProperties(type: self.type)
            let encodedProperties = String(decoding: try encoder.encode(properties), as: UTF8.self)
            try container.encode(encodedProperties, forKey: .encodedProperties)
        }
    }

    /// The plugin product of a Swift package.
    public final class Plugin: Product {
        /// The name of the plugin targets to vend as a product.
        public let targets: [String]

        init(name: String, targets: [String]) {
            self.targets = targets
            super.init(name: name)
        }

        public override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("plugin", forKey: .type)
            try container.encode(targets, forKey: .targets)
        }
    }

    /// The name of the product type to encode.
    private class var productTypeName: String { return "unknown" }
    
    /// The string representation of any additional product properties. By
    /// storing these as a separate encoded blob, the properties can be a
    /// private contract between PackageDescription and whatever client will
    /// interprest them, without libSwiftPM needing to know the contents.
    private var encodedProperties: String? { return .none }

    enum CodingKeys: String, CodingKey {
        case type, name, targets, encodedProperties
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.productTypeName, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(encodedProperties, forKey: .encodedProperties)
    }
}


extension Product {
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
    ///         Leave this parameter unspecified to let the Swift Package Manager choose between static or dynamic linking (recommended).
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
    
    /// Creates an plugin package product.
    ///
    /// - Parameters:
    ///     - name: The name of the plugin product.
    ///     - targets: The plugin targets to vend as a product.
    @available(_PackageDescription, introduced: 5.5)
    public static func plugin(
        name: String,
        targets: [String]
    ) -> Product {
        return Plugin(name: name, targets: targets)
    }
}
