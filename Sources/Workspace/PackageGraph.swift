/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageGraph

extension PackageGraph {

    /// Loads a package graph from a root package using the resources associated with a particular `swift` executable.
    ///
    /// - Parameters:
    ///     - package: The absolute path of the root package.
    ///     - swiftExecutable: The absolute path of a `swift` executable.
    ///         Its associated resources will be used by the loader.
    public static func loadGraph(
        from package: AbsolutePath,
        with swiftExecutable: AbsolutePath) throws -> PackageGraph {

        let resources = try UserManifestResources(swiftExectuable: swiftExecutable)
        let loader = ManifestLoader(manifestResources: resources)
        let workspace = Workspace.create(forRootPackage: package, manifestLoader: loader)
        return workspace.loadPackageGraph(root: package, diagnostics: DiagnosticsEngine())
    }
}
