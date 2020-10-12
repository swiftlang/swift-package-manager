/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A dependency description along with its associated product filter.
public struct FilteredDependencyDescription: Codable {

    /// Creates a filtered dependency.
    ///
    /// - Parameters:
    ///   - declaration: The raw dependency.
    ///   - productFilter: The product filter to apply.
    public init(declaration: PackageDependencyDescription, productFilter: ProductFilter) {
        self.declaration = declaration
        self.productFilter = productFilter
    }

    /// The loaded dependency declaration.
    public let declaration: PackageDependencyDescription

    /// The resolved product filter.
    public let productFilter: ProductFilter
}
