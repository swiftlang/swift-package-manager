//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import OrderedCollections
import PackageLoading
import PackageModel

import func TSCBasic.topologicalSort
import func TSCBasic.bestMatch

extension PackageGraph {
    /// Load the package graph for the given package path.
    public static func load(
        root: PackageGraphRoot,
        identityResolver: IdentityResolver,
        additionalFileRules: [FileRuleDescription] = [],
        externalManifests: OrderedCollections.OrderedDictionary<PackageIdentity, (manifest: Manifest, fs: FileSystem)>,
        requiredDependencies: [PackageReference] = [],
        unsafeAllowedPackages: Set<PackageReference> = [],
        binaryArtifacts: [PackageIdentity: [String: BinaryArtifact]],
        shouldCreateMultipleTestProducts: Bool = false,
        createREPLProduct: Bool = false,
        customPlatformsRegistry: PlatformRegistry? = .none,
        customXCTestMinimumDeploymentTargets: [PackageModel.Platform: PlatformVersion]? = .none,
        testEntryPointPath: AbsolutePath? = nil,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws -> PackageGraph {

        let observabilityScope = observabilityScope.makeChildScope(description: "Loading Package Graph")

        // Create a map of the manifests, keyed by their identity.
        var manifestMap = externalManifests
        // prefer roots
        root.manifests.forEach {
            manifestMap[$0.key] = ($0.value, fileSystem)
        }
        let successors: (GraphLoadingNode) -> [GraphLoadingNode] = { node in
            node.requiredDependencies.compactMap{ dependency in
                return manifestMap[dependency.identity].map { (manifest, fileSystem) in
                    GraphLoadingNode(
                        identity: dependency.identity,
                        manifest: manifest,
                        productFilter: dependency.productFilter,
                        fileSystem: fileSystem
                    )
                }
            }
        }

        // Construct the root root dependencies set.
        let rootDependencies = Set(root.dependencies.compactMap{
            manifestMap[$0.identity]?.manifest
        })
        let rootManifestNodes = root.packages.map { identity, package in
            GraphLoadingNode(identity: identity, manifest: package.manifest, productFilter: .everything, fileSystem: fileSystem)
        }
        let rootDependencyNodes = root.dependencies.lazy.compactMap { (dependency: PackageDependency) -> GraphLoadingNode? in
            manifestMap[dependency.identity].map {
                GraphLoadingNode(
                    identity: dependency.identity,
                    manifest: $0.manifest,
                    productFilter: dependency.productFilter,
                    fileSystem: $0.fs
                )
            }
        }
        let inputManifests = rootManifestNodes + rootDependencyNodes

        // Collect the manifests for which we are going to build packages.
        var allNodes: [GraphLoadingNode]

        // Detect cycles in manifest dependencies.
        if let cycle = findCycle(inputManifests, successors: successors) {
            observabilityScope.emit(PackageGraphError.cycleDetected(cycle))
            // Break the cycle so we can build a partial package graph.
            allNodes = inputManifests.filter({ $0.manifest != cycle.cycle[0] })
        } else {
            // Sort all manifests toplogically.
            allNodes = try topologicalSort(inputManifests, successors: successors)
        }

        var flattenedManifests: [PackageIdentity: GraphLoadingNode] = [:]
        for node in allNodes {
            if let existing = flattenedManifests[node.identity] {
                let merged = GraphLoadingNode(
                    identity: node.identity,
                    manifest: node.manifest,
                    productFilter: existing.productFilter.union(node.productFilter),
                    fileSystem: node.fileSystem
                )
                flattenedManifests[node.identity] = merged
            } else {
                flattenedManifests[node.identity] = node
            }
        }
        // sort by identity
        allNodes = flattenedManifests.keys.sorted().map { flattenedManifests[$0]! } // force unwrap fine since we are iterating on keys

        // Create the packages.
        var manifestToPackage: [Manifest: Package] = [:]
        for node in allNodes {
            let nodeObservabilityScope = observabilityScope.makeChildScope(
                description: "loading package \(node.identity)",
                metadata: .packageMetadata(identity: node.identity, kind: node.manifest.packageKind)
            )

            let manifest = node.manifest
            // Derive the path to the package.
            //
            // FIXME: Lift this out of the manifest.
            let packagePath = manifest.path.parentDirectory
            nodeObservabilityScope.trap {
                // Create a package from the manifest and sources.
                let builder = PackageBuilder(
                    identity: node.identity,
                    manifest: manifest,
                    productFilter: node.productFilter,
                    path: packagePath,
                    additionalFileRules: additionalFileRules,
                    binaryArtifacts: binaryArtifacts[node.identity] ?? [:],                
                    shouldCreateMultipleTestProducts: shouldCreateMultipleTestProducts,
                    testEntryPointPath: testEntryPointPath,
                    createREPLProduct: manifest.packageKind.isRoot ? createREPLProduct : false,
                    fileSystem: node.fileSystem,
                    observabilityScope: nodeObservabilityScope
                )
                let package = try builder.construct()
                manifestToPackage[manifest] = package

                // Throw if any of the non-root package is empty.
                if package.targets.isEmpty // System packages have targets in the package but not the manifest.
                    && package.manifest.targets.isEmpty // An unneeded dependency will not have loaded anything from the manifest.
                    && !manifest.packageKind.isRoot {
                    throw PackageGraphError.noModules(package)
                }
            }
        }

        // Resolve dependencies and create resolved packages.
        let resolvedPackages = try createResolvedPackages(
            nodes: allNodes,
            identityResolver: identityResolver,
            manifestToPackage: manifestToPackage,
            rootManifests: root.manifests,
            unsafeAllowedPackages: unsafeAllowedPackages,
            platformRegistry: customPlatformsRegistry ?? .default,
            derivedXCTestPlatformProvider: { declared in
                if let customXCTestMinimumDeploymentTargets {
                    return customXCTestMinimumDeploymentTargets[declared]
                } else {
                    return MinimumDeploymentTarget.default.computeXCTestMinimumDeploymentTarget(for: declared)
                }
            },
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )

        let rootPackages = resolvedPackages.filter{ root.manifests.values.contains($0.manifest) }
        checkAllDependenciesAreUsed(rootPackages, observabilityScope: observabilityScope)

        return try PackageGraph(
            rootPackages: rootPackages,
            rootDependencies: resolvedPackages.filter{ rootDependencies.contains($0.manifest) },
            dependencies: requiredDependencies,
            binaryArtifacts: binaryArtifacts
        )
    }
}

private func checkAllDependenciesAreUsed(_ rootPackages: [ResolvedPackage], observabilityScope: ObservabilityScope) {
    for package in rootPackages {
        // List all dependency products dependent on by the package targets.
        let productDependencies: Set<ResolvedProduct> = Set(package.targets.flatMap({ target in
            return target.dependencies.compactMap({ targetDependency in
                switch targetDependency {
                case .product(let product, _):
                    return product
                case .target:
                    return nil
                }
            })
        }))

        for dependency in package.dependencies {
            // We continue if the dependency contains executable products to make sure we don't
            // warn on a valid use-case for a lone dependency: swift run dependency executables.
            guard !dependency.products.contains(where: { $0.type == .executable }) else {
                continue
            }
            // Skip this check if this dependency is a system module because system module packages
            // have no products.
            //
            // FIXME: Do/should we print a warning if a dependency has no products?
            if dependency.products.isEmpty && dependency.targets.filter({ $0.type == .systemModule }).count == 1 {
                continue
            }

            // Skip this check if this dependency contains a command plugin product.
            if dependency.products.contains(where: \.isCommandPlugin) {
                continue
            }
            
            // Make sure that any diagnostics we emit below are associated with the package.
            let packageDiagnosticsScope = observabilityScope.makeChildScope(
                description: "Package Dependency Validation",
                metadata: package.underlyingPackage.diagnosticsMetadata
            )

            // Otherwise emit a warning if none of the dependency package's products are used.
            let dependencyIsUsed = dependency.products.contains(where: productDependencies.contains)
            if !dependencyIsUsed && !observabilityScope.errorsReportedInAnyScope {
                packageDiagnosticsScope.emit(.unusedDependency(dependency.identity.description))
            }
        }
    }
}

fileprivate extension ResolvedProduct {
    /// Returns true if and only if the product represents a command plugin target.
    var isCommandPlugin: Bool {
        guard type == .plugin else { return false }
        guard let target = underlyingProduct.targets.compactMap({ $0 as? PluginTarget }).first else { return false }
        guard case .command = target.capability else { return false }
        return true
    }
}

/// Create resolved packages from the loaded packages.
private func createResolvedPackages(
    nodes: [GraphLoadingNode],
    identityResolver: IdentityResolver,
    manifestToPackage: [Manifest: Package],
    // FIXME: This shouldn't be needed once <rdar://problem/33693433> is fixed.
    rootManifests: [PackageIdentity: Manifest],
    unsafeAllowedPackages: Set<PackageReference>,
    platformRegistry: PlatformRegistry,
    derivedXCTestPlatformProvider: @escaping (_ declared: PackageModel.Platform) -> PlatformVersion?,
    fileSystem: FileSystem,
    observabilityScope: ObservabilityScope
) throws -> [ResolvedPackage] {
    // Create memoized packages from the input manifests.
    let memoizedPackages: [MemoizedResolvedPackage] = nodes.compactMap{ node in
        guard let package = manifestToPackage[node.manifest] else {
            return nil
        }
        let isAllowedToVendUnsafeProducts = unsafeAllowedPackages.contains{ $0.identity == package.identity }
        
        let allowedToOverride = rootManifests.values.contains(node.manifest)
        return MemoizedResolvedPackage(
            package,
            productFilter: node.productFilter,
            isAllowedToVendUnsafeProducts: isAllowedToVendUnsafeProducts,
            allowedToOverride: allowedToOverride
        )
    }

    // Create a map of memoized packages keyed by package identity.
    // This is guaranteed to be unique so we can use spm_createDictionary
    let packagesByIdentity: [PackageIdentity: MemoizedResolvedPackage] = memoizedPackages.spm_createDictionary{
        return ($0.package.identity, $0)
    }

    // Resolve module aliases, if specified, for targets and their dependencies
    // across packages. Aliasing will result in target renaming.
    let moduleAliasingUsed = try resolveModuleAliases(
        memoizedPackages: memoizedPackages,
        observabilityScope: observabilityScope
    )

    // Scan and validate the dependencies
    for memoizedPackage in memoizedPackages {
        let package = memoizedPackage.package

        let packageObservabilityScope = observabilityScope.makeChildScope(
            description: "Validating package dependencies",
            metadata: package.diagnosticsMetadata
        )
        
        var dependencies = OrderedCollections.OrderedDictionary<PackageIdentity, MemoizedResolvedPackage>()
        var dependenciesByNameForTargetDependencyResolution = [String: MemoizedResolvedPackage]()
        var dependencyNamesForTargetDependencyResolutionOnly = [PackageIdentity: String]()

        // Establish the manifest-declared package dependencies.
        package.manifest.dependenciesRequired(for: memoizedPackage.productFilter).forEach { dependency in
            let dependencyPackageRef = dependency.packageRef

            // Otherwise, look it up by its identity.
            if let resolvedPackage = packagesByIdentity[dependency.identity] {
                // check if this resolved package already listed in the dependencies
                // this means that the dependencies share the same identity
                // FIXME: this works but the way we find out about this is based on a side effect, need to improve it
                guard dependencies[resolvedPackage.package.identity] == nil else {
                    let error = PackageGraphError.dependencyAlreadySatisfiedByIdentifier(
                        package: package.identity.description,
                        dependencyLocation: dependencyPackageRef.locationString,
                        otherDependencyURL: resolvedPackage.package.manifest.packageLocation,
                        identity: dependency.identity)
                    return packageObservabilityScope.emit(error)
                }

                // check if the resolved package location is the same as the dependency one
                // if not, this means that the dependencies share the same identity
                // which only allowed when overriding
                if resolvedPackage.package.manifest.canonicalPackageLocation != dependencyPackageRef.canonicalLocation && !resolvedPackage.allowedToOverride {
                    let error = PackageGraphError.dependencyAlreadySatisfiedByIdentifier(
                        package: package.identity.description,
                        dependencyLocation: dependencyPackageRef.locationString,
                        otherDependencyURL: resolvedPackage.package.manifest.packageLocation,
                        identity: dependency.identity)
                    // 9/2021 this is currently emitting a warning only to support
                    // backwards compatibility with older versions of SwiftPM that had too weak of a validation
                    // we will upgrade this to an error in a few versions to tighten up the validation
                    if dependency.explicitNameForTargetDependencyResolutionOnly == .none ||
                        resolvedPackage.package.manifest.displayName == dependency.explicitNameForTargetDependencyResolutionOnly {
                        packageObservabilityScope.emit(warning: error.description + ". this will be escalated to an error in future versions of SwiftPM.")
                    } else {
                        return packageObservabilityScope.emit(error)
                    }
                } else if resolvedPackage.package.manifest.canonicalPackageLocation == dependencyPackageRef.canonicalLocation &&
                            resolvedPackage.package.manifest.packageLocation != dependencyPackageRef.locationString  &&
                            !resolvedPackage.allowedToOverride {
                    packageObservabilityScope.emit(info: "dependency on '\(resolvedPackage.package.identity)' is represented by similar locations ('\(resolvedPackage.package.manifest.packageLocation)' and '\(dependencyPackageRef.locationString)') which are treated as the same canonical location '\(dependencyPackageRef.canonicalLocation)'.")
                }

                // checks if two dependencies have the same explicit name which can cause target based dependency package lookup issue
                if let explicitDependencyName = dependency.explicitNameForTargetDependencyResolutionOnly {
                    if let previouslyResolvedPackage = dependenciesByNameForTargetDependencyResolution[explicitDependencyName] {
                        let error = PackageGraphError.dependencyAlreadySatisfiedByName(
                            package: package.identity.description,
                            dependencyLocation: dependencyPackageRef.locationString,
                            otherDependencyURL: previouslyResolvedPackage.package.manifest.packageLocation,
                            name: explicitDependencyName)
                        return packageObservabilityScope.emit(error)
                    }
                }

                // checks if two dependencies have the same implicit (identity based) name which can cause target based dependency package lookup issue
                if let previouslyResolvedPackage = dependenciesByNameForTargetDependencyResolution[dependency.identity.description] {
                    let error = PackageGraphError.dependencyAlreadySatisfiedByName(
                        package: package.identity.description,
                        dependencyLocation: dependencyPackageRef.locationString,
                        otherDependencyURL: previouslyResolvedPackage.package.manifest.packageLocation,
                        name: dependency.identity.description)
                    return packageObservabilityScope.emit(error)
                }

                let nameForTargetDependencyResolution = dependency.explicitNameForTargetDependencyResolutionOnly ?? dependency.identity.description
                dependenciesByNameForTargetDependencyResolution[nameForTargetDependencyResolution] = resolvedPackage
                dependencyNamesForTargetDependencyResolutionOnly[resolvedPackage.package.identity] = nameForTargetDependencyResolution

                dependencies[resolvedPackage.package.identity] = resolvedPackage
            }
        }

        memoizedPackage.dependencies = Array(dependencies.values)
        memoizedPackage.dependencyNamesForTargetDependencyResolutionOnly = dependencyNamesForTargetDependencyResolutionOnly

        memoizedPackage.defaultLocalization = package.manifest.defaultLocalization

        memoizedPackage.platforms = computePlatforms(
            package: package,
            platformRegistry: platformRegistry,
            derivedXCTestPlatformProvider: derivedXCTestPlatformProvider
        )

        // Create memoized resolved targets for each target in the package.
        let memoizedTargets = package.targets
            .map { MemoizedResolvedTarget(target: $0, observabilityScope: packageObservabilityScope) }
        memoizedPackage.targets = memoizedTargets

        // Establish dependencies between the targets. A target can only depend on another target present in the same package.
        let targetMap = memoizedTargets.spm_createDictionary({ ($0.target, $0) })
        for memoizedTarget in memoizedTargets {
            memoizedTarget.dependencies += try memoizedTarget.target.dependencies.compactMap { dependency in
                switch dependency {
                case .target(let targetDependency, let conditions):
                    guard let memoizedTargetDependency = targetMap[targetDependency] else {
                        throw InternalError("unknown target \(targetDependency.name)")
                    }
                    return .target(memoizedTargetDependency, conditions: conditions)
                case .product:
                    return nil
                }
            }
            memoizedTarget.defaultLocalization = memoizedPackage.defaultLocalization
            memoizedTarget.platforms = memoizedPackage.platforms
        }

        // Create memoized resolved products for each product in the package. A product can only contain a target
        // present in the same package.
        memoizedPackage.products = try package.products.map {
            try MemoizedResolvedProduct(product: $0, memoizedPackage: memoizedPackage, targets: $0.targets.map {
                guard let target = targetMap[$0] else {
                    throw InternalError("unknown target \($0)")
                }
                return target
            })
        }

        // add registry metadata if available
        if fileSystem.exists(package.path.appending(component: RegistryReleaseMetadataStorage.fileName)) {
            memoizedPackage.registryMetadata = try RegistryReleaseMetadataStorage.load(
                from: package.path.appending(component: RegistryReleaseMetadataStorage.fileName),
                fileSystem: fileSystem
            )
        }
    }

    var duplicateProductsChecker = DuplicateProductsChecker(
        memoizedPackages: memoizedPackages,
        moduleAliasingUsed: moduleAliasingUsed,
        observabilityScope: observabilityScope
    )
    try duplicateProductsChecker.run(lookupByProductIDs: moduleAliasingUsed, observabilityScope: observabilityScope)

    // The set of all target names.
    var allTargetNames = Set<String>()

    // Track if multiple targets are found with the same name.
    var foundDuplicateTarget = false

    // Do another pass and establish product dependencies of each target.
    for memoizedPackage in memoizedPackages {
        let package = memoizedPackage.package

        let packageObservabilityScope = observabilityScope.makeChildScope(
            description: "Validating package targets",
            metadata: package.diagnosticsMetadata
        )

        // Get all implicit system library dependencies in this package.
        let implicitSystemTargetDeps = memoizedPackage.dependencies
            .flatMap({ $0.targets })
            .filter({
                if case let systemLibrary as SystemLibraryTarget = $0.target {
                    return systemLibrary.isImplicit
                }
                return false
            })

        let packageDoesNotSupportProductAliases = memoizedPackage.package.doesNotSupportProductAliases
        let lookupByProductIDs = !packageDoesNotSupportProductAliases && 
            (memoizedPackage.package.manifest.disambiguateByProductIDs || moduleAliasingUsed)

        // Get all the products from dependencies of this package.
        let productDependencies = memoizedPackage.dependencies
            .flatMap { (dependency: MemoizedResolvedPackage) -> [MemoizedResolvedProduct] in
                // Filter out synthesized products such as tests and implicit executables.
                // Check if a dependency product is explicitly declared as a product in its package manifest
                let manifestProducts = dependency.package.manifest.products.lazy.map { $0.name }
                let explicitProducts = dependency.package.products.filter { manifestProducts.contains($0.name) }
                let explicitIdsOrNames = Set(explicitProducts.lazy.map({ lookupByProductIDs ? $0.identity : $0.name }))
                return dependency.products.filter {
                    if lookupByProductIDs {
                        return explicitIdsOrNames.contains($0.product.identity)
                    } else {
                        return explicitIdsOrNames.contains($0.product.name)
                    }
                }
            }

        let productDependencyMap: [String: MemoizedResolvedProduct]
        if lookupByProductIDs {
            productDependencyMap = try Dictionary(uniqueKeysWithValues: productDependencies.map {
                guard let packageName = memoizedPackage.dependencyNamesForTargetDependencyResolutionOnly[$0.memoizedPackage.package.identity] else {
                    throw InternalError("could not determine name for dependency on package '\($0.memoizedPackage.package.identity)' from package '\(memoizedPackage.package.identity)'")
                }
                let key = "\(packageName.lowercased())_\($0.product.name)"
                return (key, $0)
            })
        } else {
            productDependencyMap = try Dictionary(
                productDependencies.map { ($0.product.name, $0) },
                uniquingKeysWith: { lhs, _ in
                    let duplicates = productDependencies.filter { $0.product.name == lhs.product.name }
                    throw emitDuplicateProductDiagnostic(
                        productName: lhs.product.name,
                        packages: duplicates.map(\.memoizedPackage.package),
                        moduleAliasingUsed: moduleAliasingUsed,
                        observabilityScope: observabilityScope
                    )
                }
            )
        }

        // Establish dependencies in each target.
        for memoizedTarget in memoizedPackage.targets {
            // Record if we see a duplicate target.
            foundDuplicateTarget = foundDuplicateTarget || !allTargetNames.insert(memoizedTarget.target.name).inserted

            // Directly add all the system module dependencies.
            memoizedTarget.dependencies += implicitSystemTargetDeps.map { .target($0, conditions: []) }

            // Establish product dependencies.
            for case .product(let productRef, let conditions) in memoizedTarget.target.dependencies {
                // Find the product in this package's dependency products.
                // Look it up by ID if module aliasing is used, otherwise by name.
                let product = lookupByProductIDs ? productDependencyMap[productRef.identity] : productDependencyMap[productRef.name]
                guard let product else {
                    // Only emit a diagnostic if there are no other diagnostics.
                    // This avoids flooding the diagnostics with product not
                    // found errors when there are more important errors to
                    // resolve (like authentication issues).
                    if !observabilityScope.errorsReportedInAnyScope {
                        // Emit error if a product (not target) declared in the package is also a productRef (dependency)
                        let declProductsAsDependency = package.products.filter { product in
                            lookupByProductIDs ? product.identity == productRef.identity : product.name == productRef.name
                        }.map {$0.targets}.flatMap{$0}.filter { t in
                            t.name != productRef.name
                        }
                        
                        // Find a product name from the available product dependencies that is most similar to the required product name.
                        let bestMatchedProductName = bestMatch(for: productRef.name, from: Array(allTargetNames))
                        let error = PackageGraphError.productDependencyNotFound(
                            package: package.identity.description,
                            targetName: memoizedTarget.target.name,
                            dependencyProductName: productRef.name,
                            dependencyPackageName: productRef.package,
                            dependencyProductInDecl: !declProductsAsDependency.isEmpty,
                            similarProductName: bestMatchedProductName
                        )
                        packageObservabilityScope.emit(error)
                    }
                    continue
                }

                // Starting in 5.2, and target-based dependency, we require target product dependencies to
                // explicitly reference the package containing the product, or for the product, package and
                // dependency to share the same name. We don't check this in manifest loading for root-packages so
                // we can provide a more detailed diagnostic here.
                if memoizedPackage.package.manifest.toolsVersion >= .v5_2 && productRef.package == nil {
                    let referencedPackageIdentity = product.memoizedPackage.package.identity
                    guard let referencedPackageDependency = (memoizedPackage.package.manifest.dependencies.first { package in
                        return package.identity == referencedPackageIdentity
                    }) else {
                        throw InternalError("dependency reference for \(product.memoizedPackage.package.manifest.packageLocation) not found")
                    }
                    let referencedPackageName = referencedPackageDependency.nameForTargetDependencyResolutionOnly
                    if productRef.name != referencedPackageName {
                        let error = PackageGraphError.productDependencyMissingPackage(
                            productName: productRef.name,
                            targetName: memoizedTarget.target.name,
                            packageIdentifier: referencedPackageName
                        )
                        packageObservabilityScope.emit(error)
                    }
                }

                memoizedTarget.dependencies.append(.product(product, conditions: conditions))
            }
        }
    }

    // If a target with similar name was encountered before, we emit a diagnostic.
    if foundDuplicateTarget {
        var duplicateTargets = [String: [Package]]()
        for targetName in allTargetNames.sorted() {
            let packages = memoizedPackages
                .filter({ $0.targets.contains(where: { $0.target.name == targetName }) })
                .map{ $0.package }
            if packages.count > 1 {
                duplicateTargets[targetName, default: []].append(contentsOf: packages)
            }
        }

        var potentiallyDuplicatePackages = [Pair: [String]]()
        for entry in duplicateTargets {
            // the duplicate is across exactly two packages
            if entry.value.count == 2 {
                potentiallyDuplicatePackages[Pair(package1: entry.value[0], package2: entry.value[1]), default: []].append(entry.key)
            }
        }

        var duplicateTargetsAddressed = [String]()
        for potentiallyDuplicatePackage in potentiallyDuplicatePackages {
            // more than three target matches, or all targets in the package match
            if potentiallyDuplicatePackage.value.count > 3 ||
                (potentiallyDuplicatePackage.value.sorted() == potentiallyDuplicatePackage.key.package1.targets.map({ $0.name }).sorted()
                &&
                potentiallyDuplicatePackage.value.sorted() == potentiallyDuplicatePackage.key.package2.targets.map({ $0.name }).sorted())
            {
                switch (potentiallyDuplicatePackage.key.package1.identity.registry, potentiallyDuplicatePackage.key.package2.identity.registry) {
                case (.some(let registryIdentity), .none):
                    observabilityScope.emit(
                        ModuleError.duplicateModulesScmAndRegistry(
                            regsitryPackage: registryIdentity,
                            scmPackage: potentiallyDuplicatePackage.key.package2.identity,
                            targets: potentiallyDuplicatePackage.value
                        )
                    )
                case (.none, .some(let registryIdentity)):
                    observabilityScope.emit(
                        ModuleError.duplicateModulesScmAndRegistry(
                            regsitryPackage: registryIdentity,
                            scmPackage: potentiallyDuplicatePackage.key.package1.identity,
                            targets: potentiallyDuplicatePackage.value
                        )
                    )
                default:
                    observabilityScope.emit(
                        ModuleError.duplicateModules(
                            package: potentiallyDuplicatePackage.key.package1.identity,
                            otherPackage: potentiallyDuplicatePackage.key.package2.identity,
                            targets: potentiallyDuplicatePackage.value
                        )
                    )
                }
                duplicateTargetsAddressed += potentiallyDuplicatePackage.value
            }
        }

        for entry in duplicateTargets.filter({ !duplicateTargetsAddressed.contains($0.key) }) {
            observabilityScope.emit(
                ModuleError.duplicateModule(
                    targetName: entry.key,
                    packages: entry.value.map{ $0.identity })
            )
        }
    }

    return try memoizedPackages.map { try $0.construct() }
}

func emitDuplicateProductDiagnostic(
    productName: String,
    packages: [Package],
    moduleAliasingUsed: Bool,
    observabilityScope: ObservabilityScope
) -> PackageGraphError {
    if moduleAliasingUsed {
        packages.filter { $0.doesNotSupportProductAliases }.forEach {
            // Emit an additional warning about product aliasing in case of older tools-versions.
            observabilityScope.emit(warning: "product aliasing requires tools-version 5.2 or later, so it is not supported by '\($0.identity.description)'")
        }
    }
    return PackageGraphError.duplicateProduct(
        product: productName,
        packages: packages
    )
}

fileprivate extension Package {
    var doesNotSupportProductAliases: Bool {
        // We can never use the identity based lookup for older packages because they lack the necessary information.
        return self.manifest.toolsVersion < .v5_2
    }
}

fileprivate struct Pair: Hashable {
    let package1: Package
    let package2: Package

    static func == (lhs: Pair, rhs: Pair) -> Bool {
        return lhs.package1.identity == rhs.package1.identity &&
            lhs.package2.identity == rhs.package2.identity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.package1.identity)
        hasher.combine(self.package2.identity)
    }
}

extension Product {
    var isDefaultLibrary: Bool {
        return type == .library(.automatic)
    }
}

private func computePlatforms(
    package: Package,
    platformRegistry: PlatformRegistry,
    derivedXCTestPlatformProvider: @escaping (_ declared: PackageModel.Platform) -> PlatformVersion?
) -> SupportedPlatforms {

    // the supported platforms as declared in the manifest
    let declaredPlatforms: [SupportedPlatform] = package.manifest.platforms.map { platform in
        let declaredPlatform = platformRegistry.platformByName[platform.platformName]
            ?? PackageModel.Platform.custom(name: platform.platformName, oldestSupportedVersion: platform.version)
        return SupportedPlatform(
            platform: declaredPlatform,
            version: .init(platform.version),
            options: platform.options
        )
    }

    return SupportedPlatforms(
        declared: declaredPlatforms.sorted(by: { $0.platform.name < $1.platform.name }),
        derivedXCTestPlatformProvider: derivedXCTestPlatformProvider
    )
}

// Track and override module aliases specified for targets in a package graph
private func resolveModuleAliases(
    memoizedPackages: [MemoizedResolvedPackage],
    observabilityScope: ObservabilityScope
) throws -> Bool {
    // If there are no module aliases specified, return early
    let hasAliases = memoizedPackages.contains { $0.package.targets.contains {
            $0.dependencies.contains { dep in
                if case let .product(prodRef, _) = dep {
                    return prodRef.moduleAliases != nil
                }
                return false
            }
        }
    }

    guard hasAliases else { return false }
    let aliasTracker = ModuleAliasTracker()
    for memoizedPackage in memoizedPackages {
        try aliasTracker.addTargetAliases(targets: memoizedPackage.package.targets,
                                          package: memoizedPackage.package.identity)
    }

    // Track targets that need module aliases for each package
    for memoizedPackage in memoizedPackages {
        for product in memoizedPackage.package.products {
            aliasTracker.trackTargetsPerProduct(
                product: product,
                package: memoizedPackage.package.identity
            )
        }
    }

    // Override module aliases upstream if needed
    aliasTracker.propagateAliases(observabilityScope: observabilityScope)

    // Validate sources (Swift files only) for modules being aliased.
    // Needs to be done after `propagateAliases` since aliases defined
    // upstream can be overridden.
    for memoizedPackage in memoizedPackages {
        for product in memoizedPackage.package.products {
            try aliasTracker.validateAndApplyAliases(
                product: product,
                package: memoizedPackage.package.identity,
                observabilityScope: observabilityScope
            )
        }
    }

    // Emit diagnostics for any module aliases that did not end up being applied.
    aliasTracker.diagnoseUnappliedAliases(observabilityScope: observabilityScope)

    return true
}

extension Target {
  func validateDependency(target: Target) throws {
    if self.type == .plugin && target.type == .library {
        throw PackageGraphError.unsupportedPluginDependency(
            targetName: self.name,
            dependencyName: target.name,
            dependencyType: target.type.rawValue,
            dependencyPackage: nil
        )
    }
  }

  func validateDependency(product: Product, productPackage: PackageIdentity) throws {
    if self.type == .plugin && product.type.isLibrary {
        throw PackageGraphError.unsupportedPluginDependency(
            targetName: self.name,
            dependencyName: product.name,
            dependencyType: product.type.description,
            dependencyPackage: productPackage.description
        )
    }
  }
}

/// Finds the first cycle encountered in a graph.
///
/// This is different from the one in tools support core, in that it handles equality separately from node traversal. 
/// Nodes traverse product filters, but only the manifests must be equal for there to be a cycle.
fileprivate func findCycle(
    _ nodes: [GraphLoadingNode],
    successors: (GraphLoadingNode) throws -> [GraphLoadingNode]
) rethrows -> (path: [Manifest], cycle: [Manifest])? {
    // Ordered set to hold the current traversed path.
    var path = OrderedCollections.OrderedSet<Manifest>()
    
    var fullyVisitedManifests = Set<Manifest>()

    // Function to visit nodes recursively.
    // FIXME: Convert to stack.
    func visit(
      _ node: GraphLoadingNode,
      _ successors: (GraphLoadingNode) throws -> [GraphLoadingNode]
    ) rethrows -> (path: [Manifest], cycle: [Manifest])? {
        // Once all successors have been visited, this node cannot participate
        // in a cycle.
        if fullyVisitedManifests.contains(node.manifest) {
            return nil
        }
        
        // If this node is already in the current path then we have found a cycle.
        if !path.append(node.manifest).inserted {
            let index = path.firstIndex(of: node.manifest)! // forced unwrap safe
            return (Array(path[path.startIndex..<index]), Array(path[index..<path.endIndex]))
        }

        for succ in try successors(node) {
            if let cycle = try visit(succ, successors) {
                return cycle
            }
        }
        // No cycle found for this node, remove it from the path.
        let item = path.removeLast()
        assert(item == node.manifest)
        // Track fully visited nodes
        fullyVisitedManifests.insert(node.manifest)
        return nil
    }

    for node in nodes {
        if let cycle = try visit(node, successors) {
            return cycle
        }
    }
    // Couldn't find any cycle in the graph.
    return nil
}
