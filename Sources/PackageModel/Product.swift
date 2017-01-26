/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

/// The type of product.
public enum ProductType {

    /// The type of library.
    public enum LibraryType {
        /// Static library.
        case `static`

        /// Dynamic library.
        case `dynamic`

        /// The type of library is undefined.
        case none
    }

    /// The library product type.
    case library(LibraryType)

    /// The executable product type.
    case executable

    /// The test product type.
    case test
}

extension ProductType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .test:
            return "test"
        case .executable:
            return "exe"
        case .library(.static):
            return "a"
        case .library(.dynamic):
            return "dylib"
        case .library(.none):
            return "none"
        }
    }
}

public class Product: ObjectIdentifierProtocol {
    /// The name of the product.
    public let name: String

    /// The type of product to create.
    public let type: ProductType
    
    /// The list of modules to combine to form the product.
    ///
    /// This is never empty, and is only the modules which are required to be in
    /// the product, but not necessarily their transitive dependencies.
    public let modules: [Module]

    /// Path to the main file for test product on linux.
    public var linuxMainTest: AbsolutePath {
        precondition(type == .test, "This property is only valid for test product type")
        // FIXME: This is hacky, we should get this from package builder.
        let testDirectory = modules.first{$0.isTest}!.sources.root.parentDirectory
        return testDirectory.appending(component: "LinuxMain.swift")
    }

    public init(name: String, type: ProductType, modules: [Module]) {
        precondition(!modules.isEmpty)
        self.name = name
        self.type = type
        self.modules = modules
    }

    // FIXME: Remove outname from here and move to build plan where its more appropriate.
    public var outname: RelativePath {
        switch type {
        case .executable:
            return RelativePath(name)
        case .library(.static):
            return RelativePath("lib\(name).a")
        case .library(.dynamic):
            return RelativePath("lib\(name).\(Product.dynamicLibraryExtension)")
        case .library(.none):
            fatalError("Unimplemented")
        case .test:
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
        case .test:
            return "\(base).xctest"
        default:
            return base
        }
    }
}

extension ProductType: Equatable {}
public func ==(lhs: ProductType, rhs: ProductType) -> Bool {
    switch (lhs, rhs) {
    case (.executable, .executable):
        return true
    case (.executable, _):
        return false
    case (.test, .test):
        return true
    case (.test, _):
        return false
    case (.library(let lhsType), .library(let rhsType)):
        return lhsType == rhsType
    case (.library(_), _):
        return false
    }
}
