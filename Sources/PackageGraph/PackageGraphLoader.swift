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
        let allManifests = try! topologicalSort(rootManifests) { $0.package.dependencies.map{ manifestURLMap[$0.url]! } }

        // Create the packages and convert to modules.
        var manifestToPackage: [Manifest: Package] = [:]
        for manifest in allManifests {
            let isRootPackage = rootManifestSet.contains(manifest)

            // Derive the path to the package.
            //
            // FIXME: Lift this out of the manifest.
            let packagePath = manifest.path.parentDirectory

            // Create a package from the manifest and sources.
            let builder = PackageBuilder(manifest: manifest, path: packagePath, fileSystem: fileSystem)
            let package = try builder.construct()
            manifestToPackage[manifest] = package
            
            // Throw if any of the non-root package is empty.
            if package.modules.isEmpty && !isRootPackage {
                throw PackageGraphError.noModules(package)
            }
        }
        // Resolve dependencies and create resolved packages.
        let resolvedPackages = try createResolvedPackages(allManifests: allManifests, manifestToPackage: manifestToPackage)
        // Filter out the root packages.
        let resolvedRootPackages = resolvedPackages.filter{ rootManifestSet.contains($0.manifest) }
        return PackageGraph(rootPackages: resolvedRootPackages)
    }
}

/// Create resolved packages from the loaded packages.
private func createResolvedPackages(allManifests: [Manifest], manifestToPackage: [Manifest: Package]) throws -> [ResolvedPackage] {
    var packageURLMap: [String: ResolvedPackage] = [:]
    // Resolve each package in reverse topological order of their manifest.
    return try allManifests.lazy.reversed().map { manifest in
        let package = manifestToPackage[manifest]!

        // Get all the external dependencies of this package.
        let dependencies = manifest.package.dependencies.map{ packageURLMap[$0.url]! }

        // FIXME: Temporary until we switch to product based dependencies.
        let externalModuleDependencies = dependencies.flatMap{ $0.modules.filter{ $0.type != .test } }

        // Topologically Sort all the local modules in this package.
        let modules = try! topologicalSort(package.modules, successors: { $0.dependencies })

        // Make sure these module names are unique in the graph.
        if let duplicateModules = externalModuleDependencies.lazy.map({$0.name}).duplicates(modules.lazy.map{$0.name}) {
            throw ModuleError.duplicateModule(duplicateModules.first!)
        }

        // Resolve the modules.
        var moduleToResolved = [Module: ResolvedModule]()
        let resolvedModules: [ResolvedModule] = modules.lazy.reversed().map { module in
            let moduleDependencies = module.dependencies.map{ moduleToResolved[$0]! }
            let resolvedModule = ResolvedModule(module: module, dependencies: moduleDependencies + externalModuleDependencies)
            moduleToResolved[module] = resolvedModule 
            return resolvedModule
        }

        // Create resolved products.
        let resolvedProducts = package.products.map { product in
            return ResolvedProduct(product: product, modules: product.modules.map{ moduleToResolved[$0]! })
        }
        // Create resolved package.
        let resolvedPackage = ResolvedPackage(
            package: package, dependencies: dependencies, modules: resolvedModules, products: resolvedProducts)
        packageURLMap[package.manifest.url] = resolvedPackage 
        return resolvedPackage 
    }
}

// FIXME: Possibly lift this to Basic.
private extension Array where Element: Hashable {
    // Returns the set of duplicate elements in two arrays, if any.
    func duplicates(_ other: Array<Element>) -> Set<Element>? {
        let dupes = Set(self).intersection(Set(other))
        return dupes.isEmpty ? nil : dupes
    }
}
