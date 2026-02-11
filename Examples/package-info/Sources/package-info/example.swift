//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Basics
import Workspace

@main
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
struct Example {
    static func main() async throws {
        // PREREQUISITES
        // ============

        // We need a package to work with.
        // This computes the path of this package root based on the file location
        let packagePath = try AbsolutePath(validating: #file).parentDirectory.parentDirectory.parentDirectory

        // LOADING
        // =======

        // There are several levels of information available.
        // Each takes longer to load than the level above it, but provides more detail.

<<<<<<< HEAD
        let observability = ObservabilitySystem({ print("\($0): \($1)") })
=======
        let observability = ObservabilitySystem({ print("\($0): \($1)") }, outputStream: stdoutStream, logLevel: .debug)
>>>>>>> c59ad8f2c (Fix `OutputHandler.print` method API (#9683))

        let workspace = try Workspace(forRootPackage: packagePath)

        let manifest = try await workspace.loadRootManifest(at: packagePath, observabilityScope: observability.topScope)

        let package = try await workspace.loadRootPackage(at: packagePath, observabilityScope: observability.topScope)

        let graph = try await workspace.loadPackageGraph(rootPath: packagePath, observabilityScope: observability.topScope)

        // EXAMPLES
        // ========

        // Manifest
        let products = manifest.products.map({ $0.name }).joined(separator: ", ")
        print("Products:", products)

        let targets = manifest.targets.map({ $0.name }).joined(separator: ", ")
        print("Targets:", targets)

        // Package
        let executables = package.modules.filter({ $0.type == .executable }).map({ $0.name })
        print("Executable targets:", executables)

        // PackageGraph
        let numberOfFiles = graph.reachableModules.reduce(0, { $0 + $1.sources.paths.count })
        print("Total number of source files (including dependencies):", numberOfFiles)
    }
}
