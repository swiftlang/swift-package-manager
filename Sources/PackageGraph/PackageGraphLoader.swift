/*
 This source file is part of the Swift.org open source project
 
 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import Get
import PackageLoading

/// A helper class for loading a package graph.
public struct PackageGraphLoader {
    /// The manifest loader.
    public let manifestLoader: ManifestLoader
    
    /// Create a package loader.
    public init(manifestLoader: ManifestLoader) {
        self.manifestLoader = manifestLoader
    }

    /// Load the package graph for the given package path.
    ///
    /// - Parameters:
    ///   - ignoreDependencies: If true, then skip resolution (and loading) of the package dependencies.
    public func loadPackage(at path: AbsolutePath, ignoreDependencies: Bool) throws -> PackageGraph {
        // Create the packages directory container.
        let packagesDirectory = PackagesDirectory(root: path, manifestLoader: manifestLoader)

        // Load the packages.
        let (rootPackage, externalPackages) = try packagesDirectory.loadPackages(ignoreDependencies: ignoreDependencies)

        // Convert to modules.
        //
        // FIXME: This needs to be torn about, the module conversion should be
        // done on an individual package basis.
        let (modules, externalModules, products) = try transmute(rootPackage, externalPackages: externalPackages)

        return PackageGraph(rootPackage: rootPackage, modules: modules, externalModules: Set(externalModules), products: products)
    }
}
