/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

@_exported import enum PackageDescription.ProductType

public class Product {
    /// The name of the product.
    public let name: String

    /// The type of product to create.
    public let type: ProductType
    
    /// The list of modules to combine to form the product.
    ///
    /// This is never empty, and is only the modules which are required to be in
    /// the product, but not necessarily their transitive dependencies.
    public let modules: [Module]

    public init(name: String, type: ProductType, modules: [Module]) {
        precondition(!modules.isEmpty)
        self.name = name
        self.type = type
        self.modules = modules
    }

    public var outname: RelativePath {
        switch type {
        case .Executable:
            return RelativePath(name)
        case .Library(.Static):
            return RelativePath("lib\(name).a")
        case .Library(.Dynamic):
            return RelativePath("lib\(name).\(Product.dynamicLibraryExtension)")
        case .Test:
            let base = "\(name).xctest"
            #if os(macOS)
                return RelativePath("\(base)/Contents/MacOS/\(name)")
            #else
                return RelativePath(base)
            #endif
        }
    }

    // FIXME: This needs to be come from a toolchain object, not the host
    // configuration.
#if os(macOS)
    public static let dynamicLibraryExtension = "dylib"
#else
    public static let dynamicLibraryExtension = "so"
#endif
}

extension Product: CustomStringConvertible {
    public var description: String {
        let base = outname.basename
        switch type {
        case .Test:
            return "\(base).xctest"
        default:
            return base
        }
    }
}
