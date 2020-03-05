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

extension Manifest {
    public static func createV4Manifest(
        name: String,
        path: String = "/",
        url: String = "/",
        version: TSCUtility.Version? = nil,
        toolsVersion: ToolsVersion = .v4,
        packageKind: PackageReference.Kind = .root,
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
            platforms: [],
            path: AbsolutePath(path).appending(component: Manifest.filename),
            url: url,
            version: version,
            toolsVersion: toolsVersion,
            packageKind: packageKind,
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

    public static func createManifest(
        name: String,
        defaultLocalization: String? = nil,
        platforms: [PlatformDescription] = [],
        path: String = "/",
        url: String = "/",
        version: TSCUtility.Version? = nil,
        v: ToolsVersion,
        packageKind: PackageReference.Kind = .root,
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
            defaultLocalization: defaultLocalization,
            platforms: platforms,
            path: AbsolutePath(path).appending(component: Manifest.filename),
            url: url,
            version: version,
            toolsVersion: v,
            packageKind: packageKind,
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
}

extension ProductDescription {
    public init(name: String, targets: [String]) {
        self.init(name: name, type: .library(.automatic), targets: targets)
    }
}

extension Manifest {
    public func with(url: String) -> Manifest {
        return Manifest(
            name: name,
            platforms: platforms,
            path: path,
            url: url,
            version: version,
            toolsVersion: toolsVersion,
            packageKind: packageKind,
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
}
