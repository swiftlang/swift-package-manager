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
                           name: String? = nil,
                           path: String,
                           productFilter: ProductFilter = .everything
    ) -> Self {
        return .fileSystem(identity: identity,
                           name: name,
                           path: AbsolutePath(path),
                           productFilter: productFilter)
    }

    static func fileSystem(identity: PackageIdentity? = nil,
                           name: String? = nil,
                           path: AbsolutePath,
                           productFilter: ProductFilter = .everything
    ) -> Self {
        let identity = identity ?? PackageIdentity(url: path.pathString)
        return .fileSystem(identity: identity,
                           name: name,
                           path: path,
                           productFilter: productFilter)
    }

    // backwards compatibility with existing tests
    static func local(identity: PackageIdentity? = nil,
                      name: String? = nil,
                      path: String,
                      productFilter: ProductFilter = .everything
    ) -> Self {
        return .fileSystem(identity: identity,
                           name: name,
                           path: AbsolutePath(path),
                           productFilter: productFilter)
    }

    // backwards compatibility with existing tests
    static func local(identity: PackageIdentity? = nil,
                      name: String? = nil,
                      path: AbsolutePath,
                      productFilter: ProductFilter = .everything
    ) -> Self {
        return .fileSystem(identity: identity,
                           name: name,
                           path: path,
                           productFilter: productFilter)
    }

    static func sourceControl(identity: PackageIdentity? = nil,
                              name: String? = nil,
                              location: String,
                              requirement: Requirement,
                              productFilter: ProductFilter = .everything
    ) -> Self {
        let identity = identity ?? PackageIdentity(url: location)
        return .sourceControl(identity: identity,
                              name: name,
                              location: location,
                              requirement: requirement,
                              productFilter: productFilter)
    }

    // backwards compatibility with existing tests
    static func scm(identity: PackageIdentity? = nil,
                    name: String? = nil,
                    location: String,
                    requirement: Requirement,
                    productFilter: ProductFilter = .everything
    ) -> Self {
        return .sourceControl(identity: identity,
                              name: name,
                              location: location,
                              requirement: requirement,
                              productFilter: productFilter)
    }

    static func registry(identity: String,
                         requirement: Requirement,
                         productFilter: ProductFilter = .everything
    ) -> Self {
        return .registry(identity: .plain(identity),
                         requirement: requirement,
                         productFilter: productFilter)
    }
}
