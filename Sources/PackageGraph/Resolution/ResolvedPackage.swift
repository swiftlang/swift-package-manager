//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import OrderedCollections
import PackageModel
import PackageLoading

/// A fully resolved package. Contains resolved targets, products and dependencies of the package.
public final class ResolvedPackage {
    /// The underlying package reference.
    public let underlyingPackage: Package

    // The identity of the package.
    public var identity: PackageIdentity {
        return self.underlyingPackage.identity
    }

    /// The manifest describing the package.
    public var manifest: Manifest {
        return self.underlyingPackage.manifest
    }

    /// The local path of the package.
    public var path: AbsolutePath {
        return self.underlyingPackage.path
    }

    /// The targets contained in the package.
    public let targets: [ResolvedTarget]

    /// The products produced by the package.
    public private(set) var products: [ResolvedProduct]

    /// The dependencies of the package.
    public let dependencies: [ResolvedPackage]

    /// The default localization for resources.
    public let defaultLocalization: String?

    /// The list of platforms that are supported by this target.
    public let platforms: SupportedPlatforms

    /// If the given package's source is a registry release, this provides additional metadata and signature information.
    public let registryMetadata: RegistryReleaseMetadata?

    /// Package can vend unsafe products
    let isAllowedToVendUnsafeProducts: Bool

    /// Map from package identity to the local name for target dependency resolution that has been given to that package through the dependency declaration.
    var dependencyNamesForTargetDependencyResolutionOnly: [PackageIdentity: String] = [:]

    public init(
        package: Package,
        packagesByIdentity: [PackageIdentity: Package],
        rootManifests: [PackageIdentity: Manifest],
        unsafeAllowedPackages: Set<PackageReference>,
        /// The product filter applied to the package.
        productFilter: ProductFilter,
        defaultLocalization: String?,
        platforms: SupportedPlatforms,
        fileSystem: any FileSystem,
        observabilityScope: ObservabilityScope
    ) throws {
        self.underlyingPackage = package
        self.defaultLocalization = defaultLocalization
        self.platforms = platforms

        self.isAllowedToVendUnsafeProducts = unsafeAllowedPackages.contains { $0.identity == package.identity }


        // add registry metadata if available
        if fileSystem.exists(package.path.appending(component: RegistryReleaseMetadataStorage.fileName)) {
            self.registryMetadata = try RegistryReleaseMetadataStorage.load(
                from: package.path.appending(component: RegistryReleaseMetadataStorage.fileName),
                fileSystem: fileSystem
            )
        } else {
            self.registryMetadata = nil
        }

        let packageObservabilityScope = observabilityScope.makeChildScope(
            description: "Validating package dependencies",
            metadata: package.diagnosticsMetadata
        )

        var dependencies = OrderedCollections.OrderedDictionary<PackageIdentity, ResolvedPackage>()
        var dependenciesByNameForTargetDependencyResolution = [String: Package]()
        var dependencyNamesForTargetDependencyResolutionOnly = [PackageIdentity: String]()

        // Establish the manifest-declared package dependencies.
        for dependency in package.manifest.dependenciesRequired(for: productFilter) {
            let dependencyPackageRef = dependency.packageRef

            // Otherwise, look it up by its identity.
            if let resolvedPackage = packagesByIdentity[dependency.identity] {
                // check if this resolved package already listed in the dependencies
                // this means that the dependencies share the same identity
                // FIXME: this works but the way we find out about this is based on a side effect, need to improve it
                guard dependencies[resolvedPackage.identity] == nil else {
                    let error = PackageGraphError.dependencyAlreadySatisfiedByIdentifier(
                        package: package.identity.description,
                        dependencyLocation: dependencyPackageRef.locationString,
                        otherDependencyURL: resolvedPackage.manifest.packageLocation,
                        identity: dependency.identity)
                    packageObservabilityScope.emit(error)
                    break
                }

                let allowedToOverride = rootManifests.values.contains(resolvedPackage.manifest)

                // check if the resolved package location is the same as the dependency one
                // if not, this means that the dependencies share the same identity
                // which only allowed when overriding
                if resolvedPackage.manifest.canonicalPackageLocation != dependencyPackageRef.canonicalLocation && !allowedToOverride {
                    let error = PackageGraphError.dependencyAlreadySatisfiedByIdentifier(
                        package: package.identity.description,
                        dependencyLocation: dependencyPackageRef.locationString,
                        otherDependencyURL: resolvedPackage.manifest.packageLocation,
                        identity: dependency.identity)
                    // 9/2021 this is currently emitting a warning only to support
                    // backwards compatibility with older versions of SwiftPM that had too weak of a validation.
                    // We will upgrade this to an error in a few versions to tighten up the validation
                    if dependency.explicitNameForTargetDependencyResolutionOnly == .none ||
                        resolvedPackage.manifest.displayName == dependency.explicitNameForTargetDependencyResolutionOnly {
                        packageObservabilityScope.emit(warning: error.description + ". this will be escalated to an error in future versions of SwiftPM.")
                    } else {
                        packageObservabilityScope.emit(error)
                        break
                    }
                } else if resolvedPackage.manifest.canonicalPackageLocation == dependencyPackageRef.canonicalLocation &&
                            resolvedPackage.manifest.packageLocation != dependencyPackageRef.locationString  &&
                            !allowedToOverride {
                    packageObservabilityScope.emit(info: "dependency on '\(package.identity)' is represented by similar locations ('\(package.manifest.packageLocation)' and '\(dependencyPackageRef.locationString)') which are treated as the same canonical location '\(dependencyPackageRef.canonicalLocation)'.")
                }

                // checks if two dependencies have the same explicit name which can cause target based dependency package lookup issue
                if let explicitDependencyName = dependency.explicitNameForTargetDependencyResolutionOnly {
                    if let previouslyResolvedPackage = dependenciesByNameForTargetDependencyResolution[explicitDependencyName] {
                        let error = PackageGraphError.dependencyAlreadySatisfiedByName(
                            package: package.identity.description,
                            dependencyLocation: dependencyPackageRef.locationString,
                            otherDependencyURL: previouslyResolvedPackage.manifest.packageLocation,
                            name: explicitDependencyName)
                        packageObservabilityScope.emit(error)
                        break
                    }
                }

                // checks if two dependencies have the same implicit (identity based) name which can cause target based dependency package lookup issue
                if let previouslyResolvedPackage = dependenciesByNameForTargetDependencyResolution[dependency.identity.description] {
                    let error = PackageGraphError.dependencyAlreadySatisfiedByName(
                        package: package.identity.description,
                        dependencyLocation: dependencyPackageRef.locationString,
                        otherDependencyURL: previouslyResolvedPackage.manifest.packageLocation,
                        name: dependency.identity.description)
                    packageObservabilityScope.emit(error)
                    break
                }

                let nameForTargetDependencyResolution = dependency.explicitNameForTargetDependencyResolutionOnly ?? dependency.identity.description
                dependenciesByNameForTargetDependencyResolution[nameForTargetDependencyResolution] = resolvedPackage
                dependencyNamesForTargetDependencyResolutionOnly[resolvedPackage.identity] = nameForTargetDependencyResolution

                dependencies[resolvedPackage.identity] = try ResolvedPackage(
                    package: resolvedPackage,
                    packagesByIdentity: packagesByIdentity,
                    rootManifests: rootManifests,
                    unsafeAllowedPackages: unsafeAllowedPackages,
                    productFilter: productFilter,
                    defaultLocalization: defaultLocalization,
                    platforms: platforms,
                    fileSystem: fileSystem,
                    observabilityScope: observabilityScope
                )
            }
        }

        self.dependencies = Array(dependencies.values)
        self.dependencyNamesForTargetDependencyResolutionOnly = dependencyNamesForTargetDependencyResolutionOnly

        // Create resolved target for each target in the package.
        var targetMap = [Target: ResolvedTarget]()
        for target in package.targets {
            targetMap[target] = try ResolvedTarget(
                target: target,
                // Establish dependencies between the targets. A target can only depend on another target present in the same package.
                dependencies: target.dependencies.compactMap { dependency in
                    switch dependency {
                    case .target(let target, let conditions):
                        guard let targetBuilder = targetMap[target] else {
                            throw InternalError("unknown target \(target.name)")
                        }
                        return .target(targetBuilder, conditions: conditions)
                    case .product:
                        return nil
                    }
                },
                defaultLocalization: defaultLocalization,
                platforms: platforms,
                observabilityScope: packageObservabilityScope
            )
        }

        // Create target builders for each target in the package.
        self.targets = package.targets.compactMap { targetMap[$0] }

        self.products = []

        // Create product builders for each product in the package. A product can only contain a target present in the same package.
        self.products = try package.products.map {
            try ResolvedProduct(
                package: self,
                product: $0,
                targets: $0.targets.map {
                    guard let target = targetMap[$0] else {
                        throw InternalError("unknown target \($0)")
                    }
                    return target
                },
                observabilityScope: observabilityScope
            )
        }
    }
}

extension ResolvedPackage: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public static func == (lhs: ResolvedPackage, rhs: ResolvedPackage) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}

extension ResolvedPackage: CustomStringConvertible {
    public var description: String {
        return "<ResolvedPackage: \(self.identity)>"
    }
}
