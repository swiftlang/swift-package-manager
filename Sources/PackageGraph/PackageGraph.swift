/*
 This source file is part of the Swift.org open source project
 
 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel

/// A collection of packages.
public struct PackageGraph {
    /// The root package.
    public let rootPackage: Package

    /// The complete list of contained packages, in topological order from the
    /// root package.
    public let packages: [Package]

    /// Construct a package graph directly.
    public init(rootPackage: Package, packages: [Package]) {
        self.rootPackage = rootPackage
        self.packages = packages
    }
}
