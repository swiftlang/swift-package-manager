/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import PackageLoading
import PackageModel
import Utility

enum PackageGraphError: Swift.Error {
    /// Indicates a non-root package with no modules.
    case noModules(Package)

    /// The package dependency declaration has cycle in it.
    case cycleDetected((path: [Manifest], cycle: [Manifest]))

    /// The product dependency not found.
    case productDependencyNotFound(name: String, package: String?)

    /// The product dependency was found but the package name did not match.
    case productDependencyIncorrectPackage(name: String, package: String)
}

extension PackageGraphError: FixableError {
    var error: String {
        switch self {
        case .noModules(let package):
            return "the package \(package) contains no modules"

        case .cycleDetected(let cycle):
            return "found cyclic dependency declaration: " +
                (cycle.path + cycle.cycle).map({ $0.name }).joined(separator: " -> ") +
                " -> " + cycle.cycle[0].name

        case .productDependencyNotFound(let name, _):
            return "The product dependency '\(name)' was not found."

        case .productDependencyIncorrectPackage(let name, let package):
            return "The product dependency '\(name)' on package '\(package)' was not found."
        }
    }

    var fix: String? {
        switch self {
        case .noModules:
            return "create at least one module"
        case .cycleDetected, .productDependencyNotFound, .productDependencyIncorrectPackage:
            return nil
        }
    }
}

/// A helper class for loading a package graph.
public struct PackageGraphLoader {
    /// Create a package loader.
    public init() { }

    /// Load the package graph for the given package path.
    public func load(
        root: PackageGraphRoot,
        externalManifests: [Manifest],
        engine: DiagnosticsEngine,
        fileSystem: FileSystem = localFileSystem,
        shouldCreateMultipleTestProducts: Bool = false
    ) -> PackageGraph {

        // Manifest url to manifest map.
        let manifestURLMap = Dictionary(items: (externalManifests + root.manifests).map({ ($0.url, $0) }))
        let successors: (Manifest) -> [Manifest] = { manifest in
            manifest.package.dependencies.flatMap({ manifestURLMap[$0.url] })
        }

        // Construct the root manifest and root dependencies set.
        let rootManifestSet = Set(root.manifests)
        let rootDependencies = Set(root.dependencies.flatMap({ manifestURLMap[$0.url] }))
        let inputManifests = root.manifests + rootDependencies

        // Collect the manifests for which we are going to build packages.
        let allManifests: [Manifest]

        // Detect cycles in manifest dependencies.
        if let cycle = findCycle(inputManifests, successors: successors) {
            engine.emit(PackageGraphError.cycleDetected(cycle))
            allManifests = inputManifests
        } else {
            // Sort all manifests toplogically.
            allManifests = try! topologicalSort(inputManifests, successors: successors)
        }

        // Create the packages.
        var manifestToPackage: [Manifest: Package] = [:]
        for manifest in allManifests {
            let isRootPackage = rootManifestSet.contains(manifest)

            // Derive the path to the package.
            //
            // FIXME: Lift this out of the manifest.
            let packagePath = manifest.path.parentDirectory

            // Create a package from the manifest and sources.
            let builder = PackageBuilder(
                manifest: manifest,
                path: packagePath,
                fileSystem: fileSystem,
                isRootPackage: isRootPackage,
                shouldCreateMultipleTestProducts: shouldCreateMultipleTestProducts
            )

            do {
                let package = try builder.construct()
                manifestToPackage[manifest] = package

                // Throw if any of the non-root package is empty.
                if package.modules.isEmpty && !isRootPackage {
                    throw PackageGraphError.noModules(package)
                }
            } catch {
                engine.emit(error)
            }
        }

        // Resolve dependencies and create resolved packages.
        let resolvedPackages = createResolvedPackages(
            allManifests: allManifests, manifestToPackage: manifestToPackage, engine: engine)

        return PackageGraph(
            rootPackages: resolvedPackages.filter({ rootManifestSet.contains($0.manifest) }),
            rootDependencies: resolvedPackages.filter({ rootDependencies.contains($0.manifest) })
        )
    }
}

/// Create resolved packages from the loaded packages.
private func createResolvedPackages(
    allManifests: [Manifest],
    manifestToPackage: [Manifest: Package],
    engine: DiagnosticsEngine
) -> [ResolvedPackage] {

    var packageURLMap: [String: ResolvedPackage] = [:]

    var resolvedPackages: [ResolvedPackage] = []

    // Resolve each package in reverse topological order of their manifest.
    for manifest in allManifests.lazy.reversed() {
        // We might not have a package for this manifest because we couldn't
        // load it.  So, just skip it.
        guard let package = manifestToPackage[manifest] else {
            continue
        }

        // Get all the external dependencies of this package, ignoring any
        // dependency we couldn't load.
        let dependencies = manifest.package.dependencies.flatMap({ packageURLMap[$0.url] })

        // Topologically Sort all the local modules in this package.
        let modules = try! topologicalSort(package.modules, successors: { $0.dependencies })

        // Make sure these module names are unique in the graph.
        let dependencyModuleNames = dependencies.lazy.flatMap({ $0.modules }).map({ $0.name })
        if let duplicateModules = dependencyModuleNames.duplicates(modules.lazy.map({ $0.name })) {
            engine.emit(ModuleError.duplicateModule(duplicateModules.first!))
        }

        // Add system module dependencies directly to the target's dependencies
        // because they are not representable as a product.
        let systemModulesDependencies = dependencies
            .flatMap({ $0.modules })
            .filter({ $0.type == .systemModule })
            .map(ResolvedModule.Dependency.target)

        let allProducts = dependencies.flatMap({ $0.products }).filter({ $0.type != .test })
        let allProductsMap = Dictionary(items: allProducts.map({ ($0.name, $0) }))

        // Resolve the modules.
        var moduleToResolved = [Module: ResolvedModule]()
        let resolvedModules: [ResolvedModule] = modules.lazy.reversed().map({ module in

            // Get the product dependencies for targets in this package.
            let productDependencies: [ResolvedProduct]
            switch manifest.package {
            case .v3:
                productDependencies = allProducts
            case .v4:
                productDependencies = module.productDependencies.flatMap({
                    // Find the product in this package's dependency products.
                    guard let product = allProductsMap[$0.name] else {
                        engine.emit(PackageGraphError.productDependencyNotFound(name: $0.name, package: $0.package))
                        return nil
                    }
                    // If package name is mentioned, ensure it is valid.
                    if let packageName = $0.package {
                        // Find the declared package and check that it contains
                        // the product we found above.
                        guard let package = dependencies.first(where: { $0.name == packageName }),
                              package.products.contains(product) else {
                            engine.emit(PackageGraphError.productDependencyIncorrectPackage(
                                name: $0.name, package: packageName))
                            return nil
                        }
                    }
                    return product
                })
            }

            let moduleDependencies = module.dependencies
                .map({ moduleToResolved[$0]! })
                .map(ResolvedModule.Dependency.target)
            let dependencies =
                moduleDependencies +
                systemModulesDependencies +
                productDependencies.map(ResolvedModule.Dependency.product)
            let resolvedModule = ResolvedModule(module: module, dependencies: dependencies)
            moduleToResolved[module] = resolvedModule
            return resolvedModule
        })

        // Create resolved products.
        let resolvedProducts = package.products.map({ product in
            return ResolvedProduct(product: product, modules: product.modules.map({ moduleToResolved[$0]! }))
        })
        // Create resolved package.
        let resolvedPackage = ResolvedPackage(
            package: package, dependencies: dependencies, modules: resolvedModules, products: resolvedProducts)
        packageURLMap[package.manifest.url] = resolvedPackage
        resolvedPackages.append(resolvedPackage)
    }
    return resolvedPackages
}

// FIXME: Possibly lift this to Basic.
private extension Sequence where Iterator.Element: Hashable {
    // Returns the set of duplicate elements in two arrays, if any.
    func duplicates(_ other: [Iterator.Element]) -> Set<Iterator.Element>? {
        let dupes = Set(self).intersection(Set(other))
        return dupes.isEmpty ? nil : dupes
    }
}
