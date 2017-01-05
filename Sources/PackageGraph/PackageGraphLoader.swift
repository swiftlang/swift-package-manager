/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import PackageModel
import PackageLoading
import Utility

// FIXME: This doesn't belong here.
import func POSIX.exit

enum PackageGraphError: Swift.Error {
    /// Indicates a non-root package with no modules.
    case noModules(Package)

    /// The package dependency declaration has cycle in it.
    case cycleDetected((path: [Manifest], cycle: [Manifest]))
}

extension PackageGraphError: FixableError {
    var error: String {
        switch self {
        case .noModules(let package):
            return "the package \(package) contains no modules"
        case .cycleDetected(let cycle):
            return "found cyclic dependency declaration: " +
                (cycle.path + cycle.cycle).map{$0.name}.joined(separator: " -> ") +
                " -> " + cycle.cycle[0].name
        }
    }

    var fix: String? {
        switch self {
        case .noModules(_):
            return "create at least one module"
        case .cycleDetected(_):
            return nil
        }
    }
}

/// A helper class for loading a package graph.
public struct PackageGraphLoader {
    /// Create a package loader.
    public init() { }

    /// Load the package graph for the given package path.
    public func load(rootManifests: [Manifest], externalManifests: [Manifest], fileSystem: FileSystem = localFileSystem) throws -> PackageGraph {
        let rootManifestSet = Set(rootManifests)
        // Manifest url to manifest map.
        let manifestURLMap: [String: Manifest] = Dictionary(items: (externalManifests + rootManifests).map { ($0.url, $0) })
        // Detect cycles in manifest dependencies.
        if let cycle = findCycle(rootManifests, successors: { $0.package.dependencies.map{ manifestURLMap[$0.url]! } }) {
            throw PackageGraphError.cycleDetected(cycle)
        }
        // Sort all manifests toplogically.
        //
        // This is important because we want to create packages bottom up, so we always have any dependent package.
        let allManifests = try! topologicalSort(rootManifests) { $0.package.dependencies.map{ manifestURLMap[$0.url]! } }

        // Create the packages and convert to modules.
        var packages: [Package] = []
        var map: [Package: [Module]] = [:]
        // Mapping of package url (in manifest) to created package.
        var packageURLMap: [String: Package] = [:]
        for manifest in allManifests.lazy.reversed() {
            let isRootPackage = rootManifestSet.contains(manifest)

            // Derive the path to the package.
            //
            // FIXME: Lift this out of the manifest.
            let packagePath = manifest.path.parentDirectory

            // Load all of the package dependencies.
            // We will always have all of the dependent packages because we create packages bottom up.
            let dependencies = manifest.package.dependencies.map{ packageURLMap[$0.url]! }

            // Create a package from the manifest and sources.
            //
            // FIXME: We should always load the tests, but just change which
            // tests we build based on higher-level logic. This would make it
            // easier to allow testing of external package tests.
            let builder = PackageBuilder(manifest: manifest, path: packagePath, fileSystem: fileSystem, dependencies: dependencies)
            let package = try builder.construct(includingTestModules: isRootPackage)
            packages.append(package)
            
            map[package] = package.modules + package.testModules
            packageURLMap[package.manifest.url] = package

            // Throw if any of the non-root package is empty.
            if package.modules.isEmpty && !isRootPackage {
                throw PackageGraphError.noModules(package)
            }
        }

        let (rootPackages, externalPackages) = packages.split { rootManifests.contains($0.manifest) }

        let modules = try recursiveDependencies(packages.flatMap{ map[$0] ?? [] })
        let externalModules = try recursiveDependencies(externalPackages.flatMap{ map[$0] ?? [] })

        return PackageGraph(rootPackages: rootPackages, modules: modules, externalModules: Set(externalModules))
    }
}

private func recursiveDependencies(_ modules: [Module]) throws -> [Module] {
    // FIXME: Refactor this to a common algorithm.
    var stack = modules
    var set = Set<Module>()
    var rv = [Module]()

    while stack.count > 0 {
        let top = stack.removeFirst()
        if !set.contains(top) {
            rv.append(top)
            set.insert(top)
            stack += top.dependencies
        } else {
            // See if the module in the set is actually the same.
            guard let index = set.index(of: top),
                  top.sources.root != set[index].sources.root else {
                continue;
            }
            fatalError("This should have been caught by package builder.")
        }
    }

    return rv
}
