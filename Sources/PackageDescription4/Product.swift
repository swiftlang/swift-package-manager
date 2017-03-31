/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Defines a product in the package.
public class Product {

    /// The name of the product.
    public let name: String

    init(name: String) {
        self.name = name
    }

    func toJSON() -> JSON {
        fatalError("Should be implemented by subclasses")
    }

    /// Represents an executable product.
    public final class Executable: Product {

        /// The names of the targets in this product.
        public let targets: [String]

        init(name: String, targets: [String]) {
            self.targets = targets
            super.init(name: name)
        }

        override func toJSON() -> JSON {
            return .dictionary([
                "name": .string(name),
                "product_type": .string("executable"),
                "targets": .array(targets.map(JSON.string)),
            ])
        }
    }

    /// Represents a library product.
    public final class Library: Product {

        /// The type of library product.
        public enum LibraryType: String {
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

        override func toJSON() -> JSON {
            return .dictionary([
                "name": .string(name),
                "product_type": .string("library"),
                "type": type.map({ JSON.string($0.rawValue) }) ?? .null,
                "targets": .array(targets.map(JSON.string)),
            ])
        }
    }

    /// Create a libary product.
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
}
