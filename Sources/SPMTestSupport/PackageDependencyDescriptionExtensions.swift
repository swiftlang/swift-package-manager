/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel
import TSCBasic

public extension PackageDependency {
    static func fileSystem(identity: PackageIdentity? = nil,
                           deprecatedName: String? = nil,
                           path: String,
                           productFilter: ProductFilter = .everything
    ) -> Self {
        return .fileSystem(identity: identity,
                           deprecatedName: deprecatedName,
                           path: AbsolutePath(path),
                           productFilter: productFilter)
    }

    static func fileSystem(identity: PackageIdentity? = nil,
                           deprecatedName: String? = nil,
                           path: AbsolutePath,
                           productFilter: ProductFilter = .everything
    ) -> Self {
        let identity = identity ?? PackageIdentity(url: path.pathString)
        return .fileSystem(identity: identity,
                           nameForTargetDependencyResolutionOnly: deprecatedName,
                           path: path,
                           productFilter: productFilter)
    }

    // backwards compatibility with existing tests
    static func local(identity: PackageIdentity? = nil,
                      deprecatedName: String? = nil,
                      path: String,
                      productFilter: ProductFilter = .everything
    ) -> Self {
        return .fileSystem(identity: identity,
                           deprecatedName: deprecatedName,
                           path: AbsolutePath(path),
                           productFilter: productFilter)
    }

    // backwards compatibility with existing tests
    static func local(identity: PackageIdentity? = nil,
                      deprecatedName: String? = nil,
                      path: AbsolutePath,
                      productFilter: ProductFilter = .everything
    ) -> Self {
        return .fileSystem(identity: identity,
                           deprecatedName: deprecatedName,
                           path: path,
                           productFilter: productFilter)
    }

    static func sourceControl(identity: PackageIdentity? = nil,
                              deprecatedName: String? = nil,
                              location: String,
                              requirement: SourceControl.Requirement,
                              productFilter: ProductFilter = .everything
    ) -> Self {
        let identity = identity ?? PackageIdentity(url: location)
        return .sourceControl(identity: identity,
                              nameForTargetDependencyResolutionOnly: deprecatedName,
                              location: location,
                              requirement: requirement,
                              productFilter: productFilter)
    }

    // backwards compatibility with existing tests
    static func scm(identity: PackageIdentity? = nil,
                    deprecatedName: String? = nil,
                    location: String,
                    requirement: SourceControl.Requirement,
                    productFilter: ProductFilter = .everything
    ) -> Self {
        return .sourceControl(identity: identity,
                              deprecatedName: deprecatedName,
                              location: location,
                              requirement: requirement,
                              productFilter: productFilter)
    }

    static func registry(identity: String,
                         requirement: Registry.Requirement,
                         productFilter: ProductFilter = .everything
    ) -> Self {
        return .registry(identity: .plain(identity),
                         requirement: requirement,
                         productFilter: productFilter)
    }
}

// backwards compatibility with existing tests
extension PackageDependency.SourceControl.Requirement {
    public static func upToNextMajor(from version: Version) -> Self {
        return .range(.upToNextMajor(from: version))
    }
    public static func upToNextMinor(from version: Version) -> Self {
        return .range(.upToNextMinor(from: version))
    }
}
