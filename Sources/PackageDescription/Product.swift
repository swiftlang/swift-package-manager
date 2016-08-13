/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
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

public var products = [Product]()
