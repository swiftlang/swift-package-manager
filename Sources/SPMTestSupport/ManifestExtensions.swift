/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel
import TSCBasic
import TSCUtility

public extension Manifest {
    static func createV4Manifest(
        name: String,
        path: String = "/",
        packageKind: PackageReference.Kind = .root,
        packageLocation: String = "/",
        version: TSCUtility.Version? = nil,
        toolsVersion: ToolsVersion = .v4,
        pkgConfig: String? = nil,
        providers: [SystemPackageProviderDescription]? = nil,
        cLanguageStandard: String? = nil,
        cxxLanguageStandard: String? = nil,
        swiftLanguageVersions: [SwiftLanguageVersion]? = nil,
        dependencies: [PackageDependencyDescription] = [],
        products: [ProductDescription] = [],
        targets: [TargetDescription] = []
    ) -> Manifest {
        return Manifest(
            name: name,
            path: AbsolutePath(path).appending(component: Manifest.filename),
            packageKind: packageKind,
            packageLocation: packageLocation,
            platforms: [],
            version: version,
            toolsVersion: toolsVersion,
            pkgConfig: pkgConfig,
            providers: providers,
            cLanguageStandard: cLanguageStandard,
            cxxLanguageStandard: cxxLanguageStandard,
            swiftLanguageVersions: swiftLanguageVersions,
            dependencies: dependencies,
            products: products,
            targets: targets
        )
    }

    static func createManifest(
        name: String,
        path: String = "/",
        packageKind: PackageReference.Kind = .root,
        packageLocation: String = "/",
        defaultLocalization: String? = nil,
        platforms: [PlatformDescription] = [],
        version: TSCUtility.Version? = nil,
        v: ToolsVersion,
        pkgConfig: String? = nil,
        providers: [SystemPackageProviderDescription]? = nil,
        cLanguageStandard: String? = nil,
        cxxLanguageStandard: String? = nil,
        swiftLanguageVersions: [SwiftLanguageVersion]? = nil,
        dependencies: [PackageDependencyDescription] = [],
        products: [ProductDescription] = [],
        targets: [TargetDescription] = []
    ) -> Manifest {
        return Manifest(
            name: name,
            path: AbsolutePath(path).appending(component: Manifest.filename),
            packageKind: packageKind,
            packageLocation: packageLocation,
            defaultLocalization: defaultLocalization,
            platforms: platforms,
            version: version,
            toolsVersion: v,
            pkgConfig: pkgConfig,
            providers: providers,
            cLanguageStandard: cLanguageStandard,
            cxxLanguageStandard: cxxLanguageStandard,
            swiftLanguageVersions: swiftLanguageVersions,
            dependencies: dependencies,
            products: products,
            targets: targets
        )
    }

    func with(location: String) -> Manifest {
        return Manifest(
            name: self.name,
            path: self.path,
            packageKind: self.packageKind,
            packageLocation: location,
            platforms: self.platforms,
            version: self.version,
            toolsVersion: self.toolsVersion,
            pkgConfig: self.pkgConfig,
            providers: self.providers,
            cLanguageStandard: self.cLanguageStandard,
            cxxLanguageStandard: self.cxxLanguageStandard,
            swiftLanguageVersions: self.swiftLanguageVersions,
            dependencies: self.dependencies,
            products: self.products,
            targets: self.targets
        )
    }
}
