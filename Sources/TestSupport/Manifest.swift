/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel
import Basic
import SPMUtility

extension Manifest {
    public static func createV4Manifest(
        name: String,
        path: String = "/",
        url: String = "/",
        version: SPMUtility.Version? = nil,
        manifestVersion: ManifestVersion = .v4,
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
            manifestVersion: manifestVersion,
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
        platforms: [PlatformDescription] = [],
        path: String = "/",
        url: String = "/",
        version: SPMUtility.Version? = nil,
        v: ManifestVersion,
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
            platforms: platforms,
            path: AbsolutePath(path).appending(component: Manifest.filename),
            url: url,
            version: version,
            manifestVersion: v,
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
