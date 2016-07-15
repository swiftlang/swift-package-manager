/*
 This source file is part of the Swift.org open source project
 
 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import PackageModel

/// A collection of packages.
public struct PackageGraph {
    /// The root package.
    public let rootPackage: Package

    /// The complete list of contained packages, in topological order starting
    /// with the root package.
    ///
    /// - Precondition: packages[0] === rootPackage
    public let packages: [Package]

    /// Construct a package graph directly.
    public init(rootPackage: Package) {
        self.rootPackage = rootPackage
        // This will leave the root package at the beginning, considering the relation we are providing.
        self.packages = try! topologicalSort([rootPackage], successors: { $0.dependencies })
        assert(self.rootPackage == self.packages[0])
    }
}
