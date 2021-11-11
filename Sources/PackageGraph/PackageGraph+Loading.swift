/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import PackageLoading
import PackageModel
import TSCBasic

extension PackageGraph {

    /// Load the package graph for the given package path.
    public static func load(
        root: PackageGraphRoot,
        identityResolver: IdentityResolver,
        additionalFileRules: [FileRuleDescription] = [],
        externalManifests: OrderedDictionary<PackageIdentity, Manifest>,
        requiredDependencies: Set<PackageReference> = [],
        unsafeAllowedPackages: Set<PackageReference> = [],
        binaryArtifacts: [BinaryArtifact] = [],
        xcTestMinimumDeploymentTargets: [PackageModel.Platform:PlatformVersion] = MinimumDeploymentTarget.default.xcTestMinimumDeploymentTargets,
        shouldCreateMultipleTestProducts: Bool = false,
        createREPLProduct: Bool = false,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws -> PackageGraph {

        let observabilityScope = observabilityScope.makeChildScope(description: "Loading Package Graph")

        // Create a map of the manifests, keyed by their identity.
        var manifestMap = externalManifests
        // prefer roots
        root.manifests.forEach {
            manifestMap[$0.key] = $0.value
        }

        let successors: (GraphLoadingNode) -> [GraphLoadingNode] = { node in
            node.requiredDependencies().compactMap{ dependency in
                return manifestMap[dependency.identity].map { manifest in
                    GraphLoadingNode(identity: dependency.identity, manifest: manifest, productFilter: dependency.productFilter)
                }
            }
        }

        // Construct the root manifest and root dependencies set.
        let rootManifestSet = Set(root.manifests.values)
        let rootDependencies = Set(root.dependencies.compactMap{
            manifestMap[$0.identity]
        })
        let rootManifestNodes = root.packages.map { identity, package in
            GraphLoadingNode(identity: identity, manifest: package.manifest, productFilter: .everything)
        }
        let rootDependencyNodes = root.dependencies.lazy.compactMap { (dependency: PackageDependency) -> GraphLoadingNode? in
            manifestMap[dependency.identity].map {
                GraphLoadingNode(identity: dependency.identity, manifest: $0, productFilter: dependency.productFilter)
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
                    productFilter: existing.productFilter.union(node.productFilter)
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
                    binaryArtifacts: binaryArtifacts,
                    xcTestMinimumDeploymentTargets: xcTestMinimumDeploymentTargets,
                    shouldCreateMultipleTestProducts: shouldCreateMultipleTestProducts,
                    createREPLProduct: manifest.packageKind.isRoot ? createREPLProduct : false,
                    fileSystem: fileSystem,
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
            rootManifestSet: rootManifestSet,
            unsafeAllowedPackages: unsafeAllowedPackages,
            observabilityScope: observabilityScope
        )

        let rootPackages = resolvedPackages.filter{ rootManifestSet.contains($0.manifest) }
        checkAllDependenciesAreUsed(rootPackages, observabilityScope: observabilityScope)

        return try PackageGraph(
            rootPackages: rootPackages,
            rootDependencies: resolvedPackages.filter{ rootDependencies.contains($0.manifest) },
            dependencies: requiredDependencies
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

            let dependencyIsUsed = dependency.products.contains(where: productDependencies.contains)
            if !dependencyIsUsed && !observabilityScope.errorsReportedInAnyScope {
                observabilityScope.emit(.unusedDependency(dependency.identity.description))
            }
        }
    }
}

/// Create resolved packages from the loaded packages.
private func createResolvedPackages(
    nodes: [GraphLoadingNode],
    identityResolver: IdentityResolver,
    manifestToPackage: [Manifest: Package],
    // FIXME: This shouldn't be needed once <rdar://problem/33693433> is fixed.
    rootManifestSet: Set<Manifest>,
    unsafeAllowedPackages: Set<PackageReference>,
    observabilityScope: ObservabilityScope
) throws -> [ResolvedPackage] {

    // Create package builder objects from the input manifests.
    let packageBuilders: [ResolvedPackageBuilder] = nodes.compactMap{ node in
        guard let package = manifestToPackage[node.manifest] else {
            return nil
        }
        let isAllowedToVendUnsafeProducts = unsafeAllowedPackages.contains{ $0.identity == package.identity }
        let allowedToOverride = rootManifestSet.contains(node.manifest)
        return ResolvedPackageBuilder(
            package,
            productFilter: node.productFilter,
            isAllowedToVendUnsafeProducts: isAllowedToVendUnsafeProducts,
            allowedToOverride: allowedToOverride
        )
    }

    // Create a map of package builders keyed by the package identity.
    // This is guaranteed to be unique so we can use spm_createDictionary
    let packagesByIdentity: [PackageIdentity: ResolvedPackageBuilder] = packageBuilders.spm_createDictionary{
        return ($0.package.identity, $0)
    }

    // Scan and validate the dependencies
    for packageBuilder in packageBuilders {
        let package = packageBuilder.package

        let packageObservabilityScope = observabilityScope.makeChildScope(
            description: "Validating package dependencies",
            metadata: package.diagnosticsMetadata
        )

        var dependencies = OrderedDictionary<PackageIdentity, ResolvedPackageBuilder>()
        var dependenciesByNameForTargetDependencyResolution = [String: ResolvedPackageBuilder]()

        // Establish the manifest-declared package dependencies.
        package.manifest.dependenciesRequired(for: packageBuilder.productFilter).forEach { dependency in
            // FIXME: change this validation logic to use identity instead of location
            let dependencyLocation: String
            switch dependency {
            case .fileSystem(let settings):
                dependencyLocation = settings.path.pathString
            case .sourceControl(let settings):
                switch settings.location {
                case .local(let path):
                    dependencyLocation = path.pathString
                case .remote(let url):
                    dependencyLocation = url.absoluteString
                }
            case .registry:
                // FIXME
                fatalError("registry based dependencies not implemented yet")
            }

            // Otherwise, look it up by its identity.
            if let resolvedPackage = packagesByIdentity[dependency.identity] {
                // check if this resolved package already listed in the dependencies
                // this means that the dependencies share the same identity
                // FIXME: this works but the way we find out about this is based on a side effect, need to improve it
                guard dependencies[resolvedPackage.package.identity] == nil else {
                    let error = PackageGraphError.dependencyAlreadySatisfiedByIdentifier(
                        package: package.identity.description,
                        dependencyLocation: dependencyLocation,
                        otherDependencyURL: resolvedPackage.package.manifest.packageLocation,
                        identity: dependency.identity)
                    return packageObservabilityScope.emit(error)
                }

                // check if the resolved package location is the same as the dependency one
                // if not, this means that the dependencies share the same identity
                // which only allowed when overriding
                if !LocationComparator.areEqual(resolvedPackage.package.manifest.packageLocation, dependencyLocation) && !resolvedPackage.allowedToOverride {
                    let error = PackageGraphError.dependencyAlreadySatisfiedByIdentifier(
                        package: package.identity.description,
                        dependencyLocation: dependencyLocation,
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
                }

                // checks if two dependencies have the same explicit name which can cause target based dependency package lookup issue
                if let explicitDependencyName = dependency.explicitNameForTargetDependencyResolutionOnly {
                    if let previouslyResolvedPackage = dependenciesByNameForTargetDependencyResolution[explicitDependencyName] {
                        let error = PackageGraphError.dependencyAlreadySatisfiedByName(
                            package: package.identity.description,
                            dependencyLocation: dependencyLocation,
                            otherDependencyURL: previouslyResolvedPackage.package.manifest.packageLocation,
                            name: explicitDependencyName)
                        return packageObservabilityScope.emit(error)
                    }
                }

                // checks if two dependencies have the same implicit (identity based) name which can cause target based dependency package lookup issue
                if let previouslyResolvedPackage = dependenciesByNameForTargetDependencyResolution[dependency.identity.description] {
                    let error = PackageGraphError.dependencyAlreadySatisfiedByName(
                        package: package.identity.description,
                        dependencyLocation: dependencyLocation,
                        otherDependencyURL: previouslyResolvedPackage.package.manifest.packageLocation,
                        name: dependency.identity.description)
                    return packageObservabilityScope.emit(error)
                }

                let nameForTargetDependencyResolution = dependency.explicitNameForTargetDependencyResolutionOnly ?? dependency.identity.description
                dependenciesByNameForTargetDependencyResolution[nameForTargetDependencyResolution] = resolvedPackage

                dependencies[resolvedPackage.package.identity] = resolvedPackage
            }
        }

        packageBuilder.dependencies = Array(dependencies.values)

        // Create target builders for each target in the package.
        let targetBuilders = package.targets.map{ ResolvedTargetBuilder(target: $0, observabilityScope: observabilityScope) }
        packageBuilder.targets = targetBuilders

        // Establish dependencies between the targets. A target can only depend on another target present in the same package.
        let targetMap = targetBuilders.spm_createDictionary({ ($0.target, $0) })
        for targetBuilder in targetBuilders {
            targetBuilder.dependencies += try targetBuilder.target.dependencies.compactMap { dependency in
                switch dependency {
                case .target(let target, let conditions):
                    guard let targetBuilder = targetMap[target] else {
                        throw InternalError("unknown target \(target.name)")
                    }
                    return .target(targetBuilder, conditions: conditions)
                case .product:
                    return nil
                }
            }
        }

        // Create product builders for each product in the package. A product can only contain a target present in the same package.
        packageBuilder.products = try package.products.map{
            try ResolvedProductBuilder(product: $0, packageBuilder: packageBuilder, targets: $0.targets.map {
                guard let target = targetMap[$0] else {
                    throw InternalError("unknown target \($0)")
                }
                return target
            })
        }
    }

    // Find duplicate products in the package graph.
    let duplicateProducts = packageBuilders
        .flatMap({ $0.products })
        .map({ $0.product })
        .spm_findDuplicateElements(by: \.name)
        .map({ $0[0].name })

    // Emit diagnostics for duplicate products.
    for productName in duplicateProducts {
        let packages = packageBuilders
            .filter({ $0.products.contains(where: { $0.product.name == productName }) })
            .map{ $0.package.identity.description }
            .sorted()

        observabilityScope.emit(PackageGraphError.duplicateProduct(product: productName, packages: packages))
    }

    // Remove the duplicate products from the builders.
    for packageBuilder in packageBuilders {
        packageBuilder.products = packageBuilder.products.filter({ !duplicateProducts.contains($0.product.name) })
    }

    // The set of all target names.
    var allTargetNames = Set<String>()

    // Track if multiple targets are found with the same name.
    var foundDuplicateTarget = false

    // Do another pass and establish product dependencies of each target.
    for packageBuilder in packageBuilders {
        let package = packageBuilder.package

        let packageObservabilityScope = observabilityScope.makeChildScope(
            description: "Validating package targets",
            metadata: package.diagnosticsMetadata
        )

        // Get all implicit system library dependencies in this package.
        let implicitSystemTargetDeps = packageBuilder.dependencies
            .flatMap({ $0.targets })
            .filter({
                if case let systemLibrary as SystemLibraryTarget = $0.target {
                    return systemLibrary.isImplicit
                }
                return false
            })

        // Get all the products from dependencies of this package.
        let productDependencies = packageBuilder.dependencies
            .flatMap({ $0.products })
            .filter({ $0.product.type != .test })
        let productDependencyMap = productDependencies.spm_createDictionary({ ($0.product.name, $0) })

        // Establish dependencies in each target.
        for targetBuilder in packageBuilder.targets {
            // Record if we see a duplicate target.
            foundDuplicateTarget = foundDuplicateTarget || !allTargetNames.insert(targetBuilder.target.name).inserted

            // Directly add all the system module dependencies.
            targetBuilder.dependencies += implicitSystemTargetDeps.map { .target($0, conditions: []) }

            // Establish product dependencies.
            for case .product(let productRef, let conditions) in targetBuilder.target.dependencies {
                // Find the product in this package's dependency products.
                guard let product = productDependencyMap[productRef.name] else {
                    // Only emit a diagnostic if there are no other diagnostics.
                    // This avoids flooding the diagnostics with product not
                    // found errors when there are more important errors to
                    // resolve (like authentication issues).
                    if !observabilityScope.errorsReportedInAnyScope {
                        // Emit error if a product (not target) declared in the package is also a productRef (dependency)
                        let declProductsAsDependency = package.products.filter { product in
                            product.name == productRef.name
                        }.map {$0.targets}.flatMap{$0}.filter { t in
                            t.name != productRef.name
                        }

                        let error = PackageGraphError.productDependencyNotFound(
                            package: package.identity.description,
                            targetName: targetBuilder.target.name,
                            dependencyProductName: productRef.name,
                            dependencyPackageName: productRef.package,
                            dependencyProductInDecl: !declProductsAsDependency.isEmpty
                        )
                        packageObservabilityScope.emit(error)
                    }
                    continue
                }

                // Starting in 5.2, and target-based dependency, we require target product dependencies to
                // explicitly reference the package containing the product, or for the product, package and
                // dependency to share the same name. We don't check this in manifest loading for root-packages so
                // we can provide a more detailed diagnostic here.
                if packageBuilder.package.manifest.toolsVersion >= .v5_2 && productRef.package == nil {
                    let referencedPackageIdentity = product.packageBuilder.package.identity
                    guard let referencedPackageDependency = (packageBuilder.package.manifest.dependencies.first { package in
                        return package.identity == referencedPackageIdentity
                    }) else {
                        throw InternalError("dependency reference for \(product.packageBuilder.package.manifest.packageLocation) not found")
                    }
                    let referencedPackageName = referencedPackageDependency.nameForTargetDependencyResolutionOnly
                    if productRef.name !=  referencedPackageName {
                        let error = PackageGraphError.productDependencyMissingPackage(
                            productName: productRef.name,
                            targetName: targetBuilder.target.name,
                            packageIdentifier: referencedPackageName
                        )
                        packageObservabilityScope.emit(error)
                    }
                }

                targetBuilder.dependencies.append(.product(product, conditions: conditions))
            }
        }
    }

    // If a target with similar name was encountered before, we emit a diagnostic.
    if foundDuplicateTarget {
        for targetName in allTargetNames.sorted() {
            // Find the packages this target is present in.
            let packages = packageBuilders
                .filter({ $0.targets.contains(where: { $0.target.name == targetName }) })
                .map{ $0.package.identity.description }
                .sorted()
            if packages.count > 1 {
                observabilityScope.emit(ModuleError.duplicateModule(targetName, packages))
            }
        }
    }
    return try packageBuilders.map{ try $0.construct() }
}

/// A generic builder for `Resolved` models.
private class ResolvedBuilder<T> {
    /// The constructed object, available after the first call to `construct()`.
    private var _constructedObject: T?

    /// Construct the object with the accumulated data.
    ///
    /// Note that once the object is constucted, future calls to
    /// this method will return the same object.
    final func construct() throws -> T {
        if let constructedObject = _constructedObject {
            return constructedObject
        }
        let constructedObject = try self.constructImpl()
        _constructedObject = constructedObject
        return constructedObject
    }

    /// The object construction implementation.
    func constructImpl() throws -> T {
        fatalError("Should be implemented by subclasses")
    }
}

/// Builder for resolved product.
private final class ResolvedProductBuilder: ResolvedBuilder<ResolvedProduct> {
    /// The reference to its package.
    unowned let packageBuilder: ResolvedPackageBuilder

    /// The product reference.
    let product: Product

    /// The target builders in the product.
    let targets: [ResolvedTargetBuilder]

    init(product: Product, packageBuilder: ResolvedPackageBuilder, targets: [ResolvedTargetBuilder]) {
        self.product = product
        self.packageBuilder = packageBuilder
        self.targets = targets
    }

    override func constructImpl() throws -> ResolvedProduct {
        return ResolvedProduct(
            product: product,
            targets: try targets.map{ try $0.construct() }
        )
    }
}

/// Builder for resolved target.
private final class ResolvedTargetBuilder: ResolvedBuilder<ResolvedTarget> {

    /// Enumeration to represent target dependencies.
    enum Dependency {

        /// Dependency to another target, with conditions.
        case target(_ target: ResolvedTargetBuilder, conditions: [PackageConditionProtocol])

        /// Dependency to a product, with conditions.
        case product(_ product: ResolvedProductBuilder, conditions: [PackageConditionProtocol])
    }

    /// The target reference.
    let target: Target

    /// DiagnosticsEmitter with which to emit diagnostics
    let diagnosticsEmitter: DiagnosticsEmitter

    /// The target dependencies of this target.
    var dependencies: [Dependency] = []

    init(target: Target, observabilityScope: ObservabilityScope) {
        self.target = target
        self.diagnosticsEmitter = observabilityScope.makeDiagnosticsEmitter() {
            var metadata = ObservabilityMetadata()
            metadata.targetName = target.name
            return metadata
        }
    }

    func diagnoseInvalidUseOfUnsafeFlags(_ product: ResolvedProduct) throws {
        // Diagnose if any target in this product uses an unsafe flag.
        for target in try product.recursiveTargetDependencies() {
            let declarations = target.underlyingTarget.buildSettings.assignments.keys
            for decl in declarations {
                if BuildSettings.Declaration.unsafeSettings.contains(decl) {
                    self.diagnosticsEmitter.emit(.productUsesUnsafeFlags(product: product.name, target: target.name))
                    break
                }
            }
        }
    }

    override func constructImpl() throws -> ResolvedTarget {
        let dependencies = try self.dependencies.map { dependency -> ResolvedTarget.Dependency in
            switch dependency {
            case .target(let targetBuilder, let conditions):
                return .target(try targetBuilder.construct(), conditions: conditions)
            case .product(let productBuilder, let conditions):
                let product = try productBuilder.construct()
                if !productBuilder.packageBuilder.isAllowedToVendUnsafeProducts {
                    try self.diagnoseInvalidUseOfUnsafeFlags(product)
                }
                return .product(product, conditions: conditions)
            }
        }

        return ResolvedTarget(target: target, dependencies: dependencies)
    }
}

/// Builder for resolved package.
private final class ResolvedPackageBuilder: ResolvedBuilder<ResolvedPackage> {

    /// The package reference.
    let package: Package

    /// The product filter applied to the package.
    let productFilter: ProductFilter

    /// The targets in the package.
    var targets: [ResolvedTargetBuilder] = []

    /// The products in this package.
    var products: [ResolvedProductBuilder] = []

    /// The dependencies of this package.
    var dependencies: [ResolvedPackageBuilder] = []

    let isAllowedToVendUnsafeProducts: Bool

    let allowedToOverride: Bool

    init(_ package: Package, productFilter: ProductFilter, isAllowedToVendUnsafeProducts: Bool, allowedToOverride: Bool) {
        self.package = package
        self.productFilter = productFilter
        self.isAllowedToVendUnsafeProducts = isAllowedToVendUnsafeProducts
        self.allowedToOverride = allowedToOverride
    }

    override func constructImpl() throws -> ResolvedPackage {
        return ResolvedPackage(
            package: package,
            dependencies: try dependencies.map{ try $0.construct() },
            targets: try targets.map{ try $0.construct() },
            products: try products.map{ try  $0.construct() }
        )
    }
}

/// Finds the first cycle encountered in a graph.
///
/// This is different from the one in tools support core, in that it handles equality separately from node traversal. Nodes traverse product filters, but only the manifests must be equal for there to be a cycle.
fileprivate func findCycle(
    _ nodes: [GraphLoadingNode],
    successors: (GraphLoadingNode) throws -> [GraphLoadingNode]
) rethrows -> (path: [Manifest], cycle: [Manifest])? {
    // Ordered set to hold the current traversed path.
    var path = OrderedSet<Manifest>()

    // Function to visit nodes recursively.
    // FIXME: Convert to stack.
    func visit(
      _ node: GraphLoadingNode,
      _ successors: (GraphLoadingNode) throws -> [GraphLoadingNode]
    ) rethrows -> (path: [Manifest], cycle: [Manifest])? {
        // If this node is already in the current path then we have found a cycle.
        if !path.append(node.manifest) {
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


// TODO: model package location better / encapsulate into a new type (PackageLocation) so that such comparison is reusable
// additionally move and rename CanonicalPackageIdentity to become a detail function of the PackageLocation abstraction, as it is not used otherwise
struct LocationComparator {
    static func areEqual(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs {
            return true
        }

        let canonicalLHS = CanonicalPackageIdentity(lhs)
        let canonicalRHS = CanonicalPackageIdentity(rhs)
        if canonicalLHS == canonicalRHS {
            return true
        }

        return false
    }
}
