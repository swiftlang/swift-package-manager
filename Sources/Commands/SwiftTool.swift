/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import PackageLoading
import PackageGraph

/// A common interface for swift tools
public protocol SwiftTool {
    init()
    init(args: [String])
    func run()
}

// FIXME: Find a home for this. Ultimately it might need access to some of the
// options, and we might just want the SwiftTool type to become a class.
private let sharedPackageGraphLoader = PackageGraphLoader(manifestLoader: ManifestLoader(resources: ToolDefaults()))

public extension SwiftTool {
    init() {
        self.init(args: Array(CommandLine.arguments.dropFirst()))
    }

    /// The shared package graph loader.
    var packageGraphLoader: PackageGraphLoader {
        return sharedPackageGraphLoader
    }

    /// Fetch and load the complete package at the given path.
    func loadPackage(at path: AbsolutePath, ignoreDependencies: Bool) throws -> PackageGraph {
        return try packageGraphLoader.loadPackage(at: path, ignoreDependencies: ignoreDependencies)
    }
}
