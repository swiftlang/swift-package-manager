/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/


/// Defines a product in the package.
public enum Product {

    /// An exectuable product.
    public struct ExecutableProduct {

        /// The name of the executable product.
        public let name: String

        /// The names of targets in the product.
        public let targets: [String]
    }

    /// A library product.
    public struct LibraryProduct {

        /// The type of library products.
        public enum LibraryType: String {
            case `static`
            case `dynamic`
        }

        /// The name of the library product.
        public let name: String

        /// The type of the library.
        ///
        /// If the type is unspecified, package manager will automatically choose a type.
        public let type: LibraryType?

        /// The names of targets in the product.
        public let targets: [String]
    }

    /// Executable product.
    case exe(ExecutableProduct)

    /// Library product.
    case lib(LibraryProduct)

    /// Create an executable product.
    public static func Executable(name: String, targets: [String]) -> Product {
        return .exe(ExecutableProduct(name: name, targets: targets))
    }

    /// Create a library product.
    public static func Library(name: String, type: LibraryProduct.LibraryType? = nil, targets: [String]) -> Product {
        return .lib(LibraryProduct(name: name, type: type, targets: targets))
    }

    /// Name of the product.
    public var name: String {
        switch self {
        case .exe(let p): return p.name
        case .lib(let p): return p.name
        }
    }
}

extension Product.ExecutableProduct {
    func toJSON() -> [String: JSON] {
        return [
            "name": .string(name),
            "targets": .array(targets.map(JSON.string)),
        ]
    }
}

extension Product.LibraryProduct {
    func toJSON() -> [String: JSON] {
        return [
            "name": .string(name),
            "type": type.map{ JSON.string($0.rawValue) } ?? .null,
            "targets": .array(targets.map(JSON.string)),
        ]
    }
}

extension Product {
    func toJSON() -> JSON {
        switch self {
        case .exe(let product):
            var dict = product.toJSON()
            dict["product_type"] = .string("exe")
            return .dictionary(dict)
        case .lib(let product):
            var dict = product.toJSON()
            dict["product_type"] = .string("lib")
            return .dictionary(dict)
        }
    }
}

extension Product.ExecutableProduct: Equatable {
    public static func ==(lhs: Product.ExecutableProduct, rhs: Product.ExecutableProduct) -> Bool {
        return lhs.name == rhs.name &&
               lhs.targets == rhs.targets
    }
}

extension Product.LibraryProduct: Equatable {
    public static func ==(lhs: Product.LibraryProduct, rhs: Product.LibraryProduct) -> Bool {
        return lhs.name == rhs.name &&
               lhs.type == rhs.type &&
               lhs.targets == rhs.targets
    }
}

extension Product: Equatable {
    public static func ==(lhs: Product, rhs: Product) -> Bool {
        switch (lhs, rhs) {
        case (.exe(let a), .exe(let b)):
            return a == b
        case (.exe, _):
            return false
        case (.lib(let a), .lib(let b)):
            return a == b
        case (.lib, _):
            return false
        }
    }
}
