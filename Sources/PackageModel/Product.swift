/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility

/// The type of product.
public enum ProductType: CustomStringConvertible, Equatable {

    /// The type of library.
    public enum LibraryType: String, Codable {

        /// Static library.
        case `static`

        /// Dynamic library.
        case `dynamic`

        /// The type of library is unspecified and should be decided by package manager.
        case automatic
    }

    /// A library product.
    case library(LibraryType)

    /// An executable product.
    case executable

    /// A test product.
    case test
    
    public var description: String {
        switch self {
        case .executable:
            return "executable"
        case .test:
            return "test"
        case .library(let type):
            switch type {
            case .automatic:
                return "automatic"
            case .dynamic:
                return "dynamic"
            case .static:
                return "static"
            }
        }
    }
}

public class Product: Codable {

    /// The name of the product.
    public let name: String

    /// The type of product to create.
    public let type: ProductType

    /// The list of targets to combine to form the product.
    ///
    /// This is never empty, and is only the targets which are required to be in
    /// the product, but not necessarily their transitive dependencies.
    @PolymorphicCodableArray
    public var targets: [Target]

    /// The path to linux main file.
    public let linuxMain: AbsolutePath?

    /// The suffix for REPL product name.
    public static let replProductSuffix: String = "__REPL"

    public init(name: String, type: ProductType, targets: [Target], linuxMain: AbsolutePath? = nil) {
        precondition(!targets.isEmpty)
        if type == .executable {
            assert(targets.filter({ $0.type == .executable }).count == 1,
                   "Executable products should have exactly one executable target.")
        }
        if linuxMain != nil {
            assert(type == .test, "Linux main should only be set on test products")
        }
        self.name = name
        self.type = type
        self._targets = .init(wrappedValue: targets)
        self.linuxMain = linuxMain 
    }
}

extension Product: CustomStringConvertible {
    public var description: String {
        return "<Product: \(name)>"
    }
}
