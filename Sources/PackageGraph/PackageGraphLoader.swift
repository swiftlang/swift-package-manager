/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import SourceControl
import PackageLoading
import PackageModel
import SPMUtility

struct UnusedDependencyDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: UnusedDependencyDiagnostic.self,
        name: "org.swift.diags.unused-dependency",
        defaultBehavior: .warning,
        description: {
            $0 <<< "dependency" <<< { "'\($0.dependencyName)'" } <<< "is not used by any target"
        })

    public let dependencyName: String
}

struct ProductHasNoSupportedPlatform: DiagnosticData {
    static let id = DiagnosticID(
        type: ProductHasNoSupportedPlatform.self,
        name: "org.swift.diags.\(ProductHasNoSupportedPlatform.self)",
        defaultBehavior: .error,
        description: {
            $0 <<< "the product" <<< { "'\($0.productDependency)'" }
            $0 <<< "doesn't support any of the platform required by"
            $0 <<< "the target" <<< { "'\($0.target)'" }
        })

    public let productDependency: String
    public let target: String

    init(product: String, target: String) {
        self.productDependency = product
        self.target = target
    }
}

struct ProductUsesUnsafeFlags: DiagnosticData {
    static let id = DiagnosticID(
        type: ProductUsesUnsafeFlags.self,
        name: "org.swift.diags.\(ProductUsesUnsafeFlags.self)",
        defaultBehavior: .error,
        description: {
            $0 <<< "the target" <<< { "'\($0.target)'" }
            $0 <<< "in product" <<< { "'\($0.product)'" }
            $0 <<< "contains unsafe build flags"
        })

    public let product: String
    public let target: String

    init(product: String, target: String) {
        self.product = product
        self.target = target
    }
}

enum PackageGraphError: Swift.Error {
    /// Indicates a non-root package with no targets.
    case noModules(Package)

    /// The package dependency declaration has cycle in it.
    case cycleDetected((path: [Manifest], cycle: [Manifest]))

    /// The product dependency not found.
    case productDependencyNotFound(name: String, package: String?)

    /// The product dependency was found but the package name did not match.
    case productDependencyIncorrectPackage(name: String, package: String)

    /// A product was found in multiple packages.
    case duplicateProduct(product: String, packages: [String])
}

extension PackageGraphError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .noModules(let package):
            return "package '\(package)' contains no targets"

        case .cycleDetected(let cycle):
            return "cyclic dependency declaration found: " +
                (cycle.path + cycle.cycle).map({ $0.name }).joined(separator: " -> ") +
                " -> " + cycle.cycle[0].name

        case .productDependencyNotFound(let name, _):
            return "product dependency '\(name)' not found"

        case .productDependencyIncorrectPackage(let name, let package):
            return "product dependency '\(name)' in package '\(package)' not found"

        case .duplicateProduct(let product, let packages):
            return "multiple products named '\(product)' in: \(packages.joined(separator: ", "))"
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
        config: SwiftPMConfig = SwiftPMConfig(),
        externalManifests: [Manifest],
        requiredDependencies: Set<PackageReference> = [],
        diagnostics: DiagnosticsEngine,
        fileSystem: FileSystem = localFileSystem,
        shouldCreateMultipleTestProducts: Bool = false,
        createREPLProduct: Bool = false
    ) -> PackageGraph {

        // Create a map of the manifests, keyed by their identity.
        //
        // FIXME: For now, we have to compute the identity of dependencies from
        // the URL but that shouldn't be needed after <rdar://problem/33693433>
        // Ensure that identity and package name are the same once we have an
        // API to specify identity in the manifest file
        let manifestMapSequence = root.manifests.map({ ($0.name.lowercased(), $0) }) +
            externalManifests.map({ (PackageReference.computeIdentity(packageURL: $0.url), $0) })
        let manifestMap = Dictionary(uniqueKeysWithValues: manifestMapSequence)
        let successors: (Manifest) -> [Manifest] = { manifest in
            manifest.dependencies.compactMap({
                let url = config.mirroredURL(forURL: $0.url)
                return manifestMap[PackageReference.computeIdentity(packageURL: url)]
            })
        }

        // Construct the root manifest and root dependencies set.
        let rootManifestSet = Set(root.manifests)
        let rootDependencies = Set(root.dependencies.compactMap({
            manifestMap[PackageReference.computeIdentity(packageURL: $0.url)]
        }))
        let inputManifests = root.manifests + rootDependencies

        // Collect the manifests for which we are going to build packages.
        let allManifests: [Manifest]

        // Detect cycles in manifest dependencies.
        if let cycle = findCycle(inputManifests, successors: successors) {
            diagnostics.emit(PackageGraphError.cycleDetected(cycle))
            // Break the cycle so we can build a partial package graph.
            allManifests = inputManifests.filter({ $0 != cycle.cycle[0] })
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
                diagnostics: diagnostics,
                isRootPackage: isRootPackage,
                shouldCreateMultipleTestProducts: shouldCreateMultipleTestProducts,
                createREPLProduct: isRootPackage ? createREPLProduct : false
            )

            diagnostics.wrap(with: PackageLocation.Local(name: manifest.name, packagePath: packagePath), {
                let package = try builder.construct()
                manifestToPackage[manifest] = package

                // Throw if any of the non-root package is empty.
                if package.targets.isEmpty && !isRootPackage {
                    throw PackageGraphError.noModules(package)
                }
            })
        }

        // Resolve dependencies and create resolved packages.
        let resolvedPackages = createResolvedPackages(
            allManifests: allManifests,
            config: config,
            manifestToPackage: manifestToPackage,
            rootManifestSet: rootManifestSet,
            diagnostics: diagnostics
        )

        let rootPackages = resolvedPackages.filter({ rootManifestSet.contains($0.manifest) })

        checkAllDependenciesAreUsed(rootPackages, diagnostics)

        return PackageGraph(
            rootPackages: rootPackages,
            rootDependencies: resolvedPackages.filter({ rootDependencies.contains($0.manifest) }),
            requiredDependencies: requiredDependencies
        )
    }
}

private func checkAllDependenciesAreUsed(_ rootPackages: [ResolvedPackage], _ diagnostics: DiagnosticsEngine) {
    for package in rootPackages {
        // List all dependency products dependended on by the package targets.
        let productDependencies: Set<ResolvedProduct> = Set(package.targets.flatMap({ target in
            return target.dependencies.compactMap({ targetDependency in
                switch targetDependency {
                case .product(let product):
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
            if !dependencyIsUsed {
                diagnostics.emit(data: UnusedDependencyDiagnostic(dependencyName: dependency.name))
            }
        }
    }
}

/// Create resolved packages from the loaded packages.
private func createResolvedPackages(
    allManifests: [Manifest],
    config: SwiftPMConfig,
    manifestToPackage: [Manifest: Package],
    // FIXME: This shouldn't be needed once <rdar://problem/33693433> is fixed.
    rootManifestSet: Set<Manifest>,
    diagnostics: DiagnosticsEngine
) -> [ResolvedPackage] {

    // Create package builder objects from the input manifests.
    let packageBuilders: [ResolvedPackageBuilder] = allManifests.compactMap({
        guard let package = manifestToPackage[$0] else {
            return nil
        }
        return ResolvedPackageBuilder(package)
    })

    // Create a map of package builders keyed by the package identity.
    let packageMap: [String: ResolvedPackageBuilder] = packageBuilders.spm_createDictionary({
        // FIXME: This shouldn't be needed once <rdar://problem/33693433> is fixed.
        let identity = rootManifestSet.contains($0.package.manifest) ? $0.package.name.lowercased() : PackageReference.computeIdentity(packageURL: $0.package.manifest.url)
        return (identity, $0)
    })

    // In the first pass, we wire some basic things.
    for packageBuilder in packageBuilders {
        let package = packageBuilder.package

        // Establish the manifest-declared package dependencies.
        packageBuilder.dependencies = package.manifest.dependencies.compactMap({
            let url = config.mirroredURL(forURL: $0.url)
            return packageMap[PackageReference.computeIdentity(packageURL: url)]
        })

        // Create target builders for each target in the package.
        let targetBuilders = package.targets.map({ ResolvedTargetBuilder(target: $0, diagnostics: diagnostics) })
        packageBuilder.targets = targetBuilders

        // Establish dependencies between the targets. A target can only depend on another target present in the same package.
        let targetMap = targetBuilders.spm_createDictionary({ ($0.target, $0) })
        for targetBuilder in targetBuilders {
            targetBuilder.dependencies += targetBuilder.target.dependencies.map({ targetMap[$0]! })
        }

        // Create product builders for each product in the package. A product can only contain a target present in the same package.
        packageBuilder.products = package.products.map({
            ResolvedProductBuilder(product: $0, targets: $0.targets.map({ targetMap[$0]! }))
        })
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
            .map({ $0.package.name })
            .sorted()

        diagnostics.emit(PackageGraphError.duplicateProduct(product: productName, packages: packages))
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

        // The diagnostics location for this package.
        let diagnosticLocation = { PackageLocation.Local(name: package.name, packagePath: package.path) }

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
            targetBuilder.dependencies += implicitSystemTargetDeps

            // Establish product dependencies.
            for productRef in targetBuilder.target.productDependencies {
                // Find the product in this package's dependency products.
                guard let product = productDependencyMap[productRef.name] else {
                    // Only emit a diagnostic if there are no other diagnostics.
                    // This avoids flooding the diagnostics with product not
                    // found errors when there are more important errors to
                    // resolve (like authentication issues).
                    if !diagnostics.hasErrors {
                        let error = PackageGraphError.productDependencyNotFound(name: productRef.name, package: productRef.package)
                        diagnostics.emit(error, location: diagnosticLocation())
                    }
                    continue
                }

                // If package name is mentioned, ensure it is valid.
                if let packageName = productRef.package {
                    // Find the declared package and check that it contains
                    // the product we found above.
                    guard let dependencyPackage = packageMap[packageName.lowercased()], dependencyPackage.products.contains(product) else {
                        let error = PackageGraphError.productDependencyIncorrectPackage(
                            name: productRef.name, package: packageName)
                        diagnostics.emit(error, location: diagnosticLocation())
                        continue
                    }
                }

                targetBuilder.productDeps.append(product)
            }
        }
    }

    // If a target with similar name was encountered before, we emit a diagnostic.
    if foundDuplicateTarget {
        for targetName in allTargetNames.sorted() {
            // Find the packages this target is present in.
            let packageNames = packageBuilders
                .filter({ $0.targets.contains(where: { $0.target.name == targetName }) })
                .map({ $0.package.name })
                .sorted()
            if packageNames.count > 1 {
                diagnostics.emit(ModuleError.duplicateModule(targetName, packageNames))
            }
        }
    }
    return packageBuilders.map({ $0.construct() })
}

/// A generic builder for `Resolved` models.
private class ResolvedBuilder<T>: ObjectIdentifierProtocol {

    /// The constucted object, available after the first call to `constuct()`.
    private var _constructedObject: T?

    /// Construct the object with the accumulated data.
    ///
    /// Note that once the object is constucted, future calls to
    /// this method will return the same object.
    final func construct() -> T {
        if let constructedObject = _constructedObject {
            return constructedObject
        }
        _constructedObject = constructImpl()
        return _constructedObject!
    }

    /// The object construction implementation.
    func constructImpl() -> T {
        fatalError("Should be implemented by subclasses")
    }
}

/// Builder for resolved product.
private final class ResolvedProductBuilder: ResolvedBuilder<ResolvedProduct> {

    /// The product reference.
    let product: Product

    /// The target builders in the product.
    let targets: [ResolvedTargetBuilder]

    init(product: Product, targets: [ResolvedTargetBuilder]) {
        self.product = product
        self.targets = targets
    }

    override func constructImpl() -> ResolvedProduct {
        return ResolvedProduct(
            product: product,
            targets: targets.map({ $0.construct() })
        )
    }
}

/// Builder for resolved target.
private final class ResolvedTargetBuilder: ResolvedBuilder<ResolvedTarget> {

    /// The target reference.
    let target: Target

    /// The target dependencies of this target.
    var dependencies: [ResolvedTargetBuilder] = []

    /// The product dependencies of this target.
    var productDeps: [ResolvedProductBuilder] = []

    /// The diagnostics engine.
    let diagnostics: DiagnosticsEngine

    init(target: Target, diagnostics: DiagnosticsEngine) {
        self.target = target
        self.diagnostics = diagnostics
    }

    func validateProductDependency(_ product: ResolvedProduct) {
        // Diagnose if any target in this product uses an unsafe flag.
        for target in product.targets {
            let declarations = target.underlyingTarget.buildSettings.assignments.keys
            for decl in declarations {
                if BuildSettings.Declaration.unsafeSettings.contains(decl) {
                    diagnostics.emit(data: ProductUsesUnsafeFlags(product: product.name, target: target.name))
                    break
                }
            }
        }
    }

    override func constructImpl() -> ResolvedTarget {
        var deps: [ResolvedTarget.Dependency] = []
        for dependency in dependencies {
            deps.append(.target(dependency.construct()))
        }
        for dependency in productDeps {
            let product = dependency.construct()

            // FIXME: Should we not add the dependency if validation fails?
            validateProductDependency(product)

            deps.append(.product(product))
        }

        return ResolvedTarget(
            target: target,
            dependencies: deps
        )
    }
}

/// Builder for resolved package.
private final class ResolvedPackageBuilder: ResolvedBuilder<ResolvedPackage> {

    /// The package reference.
    let package: Package

    /// The targets in the package.
    var targets: [ResolvedTargetBuilder] = []

    /// The products in this package.
    var products: [ResolvedProductBuilder] = []

    /// The dependencies of this package.
    var dependencies: [ResolvedPackageBuilder] = []

    init(_ package: Package) {
        self.package = package
    }

    override func constructImpl() -> ResolvedPackage {
        return ResolvedPackage(
            package: package,
            dependencies: dependencies.map({ $0.construct() }),
            targets: targets.map({ $0.construct() }),
            products: products.map({ $0.construct() })
        )
    }
}
