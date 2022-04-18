//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import PackageModel
import TSCBasic

public extension PackageDependency {
    static func fileSystem(identity: PackageIdentity? = nil,
                           deprecatedName: String? = nil,
                           path: AbsolutePath,
                           productFilter: ProductFilter = .everything
    ) -> Self {
        let identity = identity ?? PackageIdentity(path: path)
        return .fileSystem(identity: identity,
                           nameForTargetDependencyResolutionOnly: deprecatedName,
                           path: path,
                           productFilter: productFilter)
    }

    static func localSourceControl(identity: PackageIdentity? = nil,
                                   deprecatedName: String? = nil,
                                   path: AbsolutePath,
                                   requirement: SourceControl.Requirement,
                                   productFilter: ProductFilter = .everything
    ) -> Self {
        let identity = identity ?? PackageIdentity(path: path)
        return .localSourceControl(identity: identity,
                                   nameForTargetDependencyResolutionOnly: deprecatedName,
                                   path: path,
                                   requirement: requirement,
                                   productFilter: productFilter)
    }

    static func remoteSourceControl(identity: PackageIdentity? = nil,
                                    deprecatedName: String? = nil,
                                    url: URL,
                                    requirement: SourceControl.Requirement,
                                    productFilter: ProductFilter = .everything
    ) -> Self {
        let identity = identity ?? PackageIdentity(url: url)
        return .remoteSourceControl(identity: identity,
                                    nameForTargetDependencyResolutionOnly: deprecatedName,
                                    url: url,
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

extension PackageDependency.Registry.Requirement {
    public static func upToNextMajor(from version: Version) -> Self {
        return .range(.upToNextMajor(from: version))
    }
    public static func upToNextMinor(from version: Version) -> Self {
        return .range(.upToNextMinor(from: version))
    }
}
