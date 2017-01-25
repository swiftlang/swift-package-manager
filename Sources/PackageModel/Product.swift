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

        /// The type of library is unspecified and should be decided by package manager.
        case automatic
    }

    /// A library product.
    case library(LibraryType)

    /// An executable product.
    case executable

    /// A test product.
    case test
}

public class Product {

    /// The name of the product.
    public let name: String

    /// The type of product to create.
    public let type: ProductType

    /// The list of targets to combine to form the product.
    ///
    /// This is never empty, and is only the targets which are required to be in
    /// the product, but not necessarily their transitive dependencies.
    public let targets: [Target]

    /// The path to linux main file.
    public let linuxMain: AbsolutePath?

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
        self.targets = targets
        self.linuxMain = linuxMain 
    }
}

extension Product: CustomStringConvertible {
    public var description: String {
        return "<Product: \(name)"
    }
}

extension ProductType: Equatable {
    public static func == (lhs: ProductType, rhs: ProductType) -> Bool {
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
        case (.library, _):
            return false
        }
    }
}
