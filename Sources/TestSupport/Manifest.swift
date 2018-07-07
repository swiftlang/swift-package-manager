/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel
import Basic
import Utility

extension Manifest {
    public static func createV4Manifest(
        name: String,
        path: String = "/",
        url: String = "/",
        legacyProducts: [ProductDescription] = [],
        legacyExclude: [String] = [],
        version: Utility.Version? = nil,
        interpreterFlags: [String] = [],
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
            path: AbsolutePath(path).appending(component: Manifest.filename),
            url: url,
            legacyProducts: legacyProducts,
            legacyExclude: legacyExclude,
            version: version,
            interpreterFlags: interpreterFlags,
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
}

extension ProductDescription {
    public init(name: String, targets: [String]) {
        self.init(name: name, type: .library(.automatic), targets: targets)
    }
}
