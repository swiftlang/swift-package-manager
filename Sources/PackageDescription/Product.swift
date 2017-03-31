/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public struct Product {
    public let name: String
    public let type: ProductType
    public let modules: [String]

    public init(name: String, type: ProductType, modules: String...) {
        self.init(name: name, type: type, modules: modules)
    }

    public init(name: String, type: ProductType, modules: [String]) {
        self.name = name
        self.type = type
        self.modules = modules
    }
}

public enum LibraryType {
    case Static
    case Dynamic
}

public enum ProductType {
    case Test
    case Executable
    case Library(LibraryType)
}

extension ProductType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .Test:
            return "test"
        case .Executable:
            return "exe"
        case .Library(.Static):
            return "a"
        case .Library(.Dynamic):
            return "dylib"
        }
    }
}

extension Product {
    func toJSON() -> JSON {
        var dict: [String: JSON] = [:]
        dict["name"] = .string(name)
        dict["type"] = .string(type.description)
        dict["modules"] = .array(modules.map(JSON.string))
        return .dictionary(dict)
    }
}

extension ProductType: Equatable {
    public static func == (lhs: ProductType, rhs: ProductType) -> Bool {
        switch (lhs, rhs) {
        case (.Executable, .Executable):
            return true
        case (.Executable, _):
            return false
        case (.Test, .Test):
            return true
        case (.Test, _):
            return false
        case (.Library(let lhsType), .Library(let rhsType)):
            return lhsType == rhsType
        case (.Library, _):
            return false
        }
    }
}

extension Product: Equatable {
    public static func == (lhs: PackageDescription.Product, rhs: PackageDescription.Product) -> Bool {
        return lhs.name == rhs.name &&
               lhs.type == rhs.type &&
               lhs.modules == rhs.modules
    }
}

public var products = [Product]()
