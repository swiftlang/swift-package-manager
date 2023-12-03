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
import PackageModel

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
    public let products: [ResolvedProduct]

    /// The dependencies of the package.
    public let dependencies: [ResolvedPackage]

    /// The default localization for resources.
    public let defaultLocalization: String?

    /// The list of platforms that are supported by this target.
    public let supportedPlatforms: [SupportedPlatform]

    /// If the given package's source is a registry release, this provides additional metadata and signature information.
    public let registryMetadata: RegistryReleaseMetadata?

    private let platformVersionProvider: PlatformVersionProvider

    public init(
        package: Package,
        defaultLocalization: String?,
        supportedPlatforms: [SupportedPlatform],
        dependencies: [ResolvedPackage],
        targets: [ResolvedTarget],
        products: [ResolvedProduct],
        registryMetadata: RegistryReleaseMetadata?,
        platformVersionProvider: PlatformVersionProvider
    ) {
        self.underlyingPackage = package
        self.defaultLocalization = defaultLocalization
        self.supportedPlatforms = supportedPlatforms
        self.dependencies = dependencies
        self.targets = targets
        self.products = products
        self.registryMetadata = registryMetadata
        self.platformVersionProvider = platformVersionProvider
    }    

    public func getDerived(for platform: Platform, usingXCTest: Bool) -> SupportedPlatform {
        self.platformVersionProvider.getDerived(
            declared: self.supportedPlatforms,
            for: platform,
            usingXCTest: usingXCTest
        )
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
