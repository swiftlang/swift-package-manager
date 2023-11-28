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

import class PackageModel.Package
import struct PackageModel.PackageIdentity
import enum PackageModel.ProductFilter
import struct PackageModel.RegistryReleaseMetadata
import struct PackageModel.SupportedPlatforms

/// Caching container for resolved packages.
final class CachedResolvedPackage: Cacheable<ResolvedPackage> {
    /// The package reference.
    let package: Package

    /// The product filter applied to the package.
    let productFilter: ProductFilter

    /// Package can vend unsafe products
    let isAllowedToVendUnsafeProducts: Bool

    /// Package can be overridden
    let allowedToOverride: Bool

    /// The targets in the package.
    var targets: [CachedResolvedTarget] = []

    /// The products in this package.
    var products: [CachedResolvedProduct] = []

    /// The dependencies of this package.
    var dependencies: [CachedResolvedPackage] = []

    /// Map from package identity to the local name for target dependency resolution that has been given to that package
    /// through the dependency declaration.
    var dependencyNamesForTargetDependencyResolutionOnly: [PackageIdentity: String] = [:]

    /// The defaultLocalization for this package.
    var defaultLocalization: String? = nil

    /// The platforms supported by this package.
    var platforms: SupportedPlatforms = .init(declared: [], derivedXCTestPlatformProvider: .none)

    /// If the given package's source is a registry release, this provides additional metadata and signature
    /// information.
    var registryMetadata: RegistryReleaseMetadata?

    init(
        _ package: Package,
        productFilter: ProductFilter,
        isAllowedToVendUnsafeProducts: Bool,
        allowedToOverride: Bool
    ) {
        self.package = package
        self.productFilter = productFilter
        self.isAllowedToVendUnsafeProducts = isAllowedToVendUnsafeProducts
        self.allowedToOverride = allowedToOverride
    }

    override func constructImpl() throws -> ResolvedPackage {
        try ResolvedPackage(
            package: self.package,
            defaultLocalization: self.defaultLocalization,
            platforms: self.platforms,
            dependencies: self.dependencies.map { try $0.construct() },
            targets: self.targets.map { try $0.construct() },
            products: self.products.map { try $0.construct() },
            registryMetadata: self.registryMetadata
        )
    }
}
