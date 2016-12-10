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
    /// The root packages.
    public let rootPackages: [Package]

    /// The complete list of contained packages, in topological order starting
    /// with the root packages.
    public let packages: [Package]

    // FIXME: These are temporary.
    public let modules: [Module]
    public let externalModules: Set<Module>
    
    /// Construct a package graph directly.
    public init(rootPackages: [Package], modules: [Module], externalModules: Set<Module>) {
        self.rootPackages = rootPackages
        self.modules = modules
        self.externalModules = externalModules
        self.packages = try! topologicalSort(rootPackages, successors: { $0.dependencies })
    }

    /// A sequence of all of the products in the graph.
    ///
    /// This yields all products in topological order starting with the root package.
    public var products: AnySequence<Product> {
        return AnySequence(packages.lazy.flatMap{ $0.products })
    }
}
