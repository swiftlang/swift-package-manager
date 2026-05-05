//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import PackageModel

/// Describes an implicit dependency that will be injected into targets when
/// the package graph is built.
public struct ImplicitDependency {
    /// The package dependency in which the products will be found.
    public let package: PackageDependency

    /// The products to be added as dependencies to each target.
    public let products: [String]

    public init(package: PackageDependency, products: [String]) {
        self.package = package
        self.products = products
    }
}
