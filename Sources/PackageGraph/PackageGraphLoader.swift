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

enum PackageGraphError: Swift.Error {
    /// Indicates a non-root package with no targets.
    case noModules(Package)

    /// The package dependency declaration has cycle in it.
    case cycleDetected((path: [Manifest], cycle: [Manifest]))

    /// The product dependency not found.
    case productDependencyNotFound(name: String, package: String?)

    /// The product dependency was found but the package name did not match.
    case productDependencyIncorrectPackage(name: String, package: String)
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
        diagnostics: DiagnosticsEngine,
        fileSystem: FileSystem = localFileSystem,
        shouldCreateMultipleTestProducts: Bool = false
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
            manifest.package.dependencies.compactMap({ 
                manifestMap[PackageReference.computeIdentity(packageURL: $0.url)] 
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
                diagnostics: diagnostics,
                isRootPackage: isRootPackage,
                shouldCreateMultipleTestProducts: shouldCreateMultipleTestProducts
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
            manifestToPackage: manifestToPackage,
            rootManifestSet: rootManifestSet,
            diagnostics: diagnostics
        )

        let rootPackages = resolvedPackages.filter({ rootManifestSet.contains($0.manifest) })

        checkAllDependenciesAreUsed(rootPackages, diagnostics)

        return PackageGraph(
            rootPackages: rootPackages,
            rootDependencies: resolvedPackages.filter({ rootDependencies.contains($0.manifest) })
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
    let packageMap: [String: ResolvedPackageBuilder] = packageBuilders.createDictionary({
        // FIXME: This shouldn't be needed once <rdar://problem/33693433> is fixed.
        let identity = rootManifestSet.contains($0.package.manifest) ? $0.package.name.lowercased() : PackageReference.computeIdentity(packageURL: $0.package.manifest.url)
        return (identity, $0)
    })

    // In the first pass, we wire some basic things.
    for packageBuilder in packageBuilders {
        let package = packageBuilder.package

        // Establish the manifest-declared package dependencies.
        packageBuilder.dependencies = package.manifest.package.dependencies.compactMap({
            packageMap[PackageReference.computeIdentity(packageURL: $0.url)]
        })

        // Create target builders for each target in the package.
        let targetBuilders = package.targets.map(ResolvedTargetBuilder.init(target:))
        packageBuilder.targets = targetBuilders

        // Establish dependencies between the targets. A target can only depend on another target present in the same package.
        let targetMap = targetBuilders.createDictionary({ ($0.target, $0) })
        for targetBuilder in targetBuilders {
            targetBuilder.dependencies += targetBuilder.target.dependencies.map({ targetMap[$0]! })
        }

        // Create product builders for each product in the package. A product can only contain a target present in the same package.
        packageBuilder.products = package.products.map({
            ResolvedProductBuilder(product: $0, targets: $0.targets.map({ targetMap[$0]! }))
        })
    }

    // The set of all target names.
    var allTargetNames = Set<String>()

    // Do another pass and establish product dependencies of each target.
    for packageBuilder in packageBuilders {
        let package = packageBuilder.package

        // The diagnostics location for this package.
        let diagnosticLocation = { PackageLocation.Local(name: package.name, packagePath: package.path) }

        // Get all the system module dependencies in this package.
        let systemModulesDeps = packageBuilder.dependencies
            .flatMap({ $0.targets })
            .filter({ $0.target.type == .systemModule })

        // Get all the products from dependencies of this package.
        let productDependencies = packageBuilder.dependencies
            .flatMap({ $0.products })
            .filter({ $0.product.type != .test })
        let productDependencyMap = productDependencies.createDictionary({ ($0.product.name, $0) })

        // Establish dependencies in each target.
        for targetBuilder in packageBuilder.targets {
            // If a target with similar name was encountered before, we emit a diagnostic.
            let targetName = targetBuilder.target.name
            if allTargetNames.contains(targetName) {
                diagnostics.emit(ModuleError.duplicateModule(targetName), location: diagnosticLocation())
            }
            allTargetNames.insert(targetName)

            // Directly add all the system module dependencies.
            targetBuilder.dependencies += systemModulesDeps

            // Establish product dependencies based on the type of manifest.
            switch package.manifest.package {
            case .v3:
                targetBuilder.productDeps = productDependencies

            case .v4:
                for productRef in targetBuilder.target.productDependencies {
                    // Find the product in this package's dependency products.
                    guard let product = productDependencyMap[productRef.name] else {
                        let error = PackageGraphError.productDependencyNotFound(name: productRef.name, package: productRef.package)
                        diagnostics.emit(error, location: diagnosticLocation())
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

    init(target: Target) {
        self.target = target
    }

    override func constructImpl() -> ResolvedTarget {
        var deps: [ResolvedTarget.Dependency] = []
        for dependency in dependencies {
            deps.append(.target(dependency.construct()))
        }
        for dependency in productDeps {
            deps.append(.product(dependency.construct()))
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
