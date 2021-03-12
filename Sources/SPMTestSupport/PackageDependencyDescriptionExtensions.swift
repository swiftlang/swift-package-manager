/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel
import TSCBasic

public extension PackageDependencyDescription {
    static func local(identity: PackageIdentity? = nil,
                      name: String? = nil,
                      path: String,
                      productFilter: ProductFilter = .everything
    ) -> PackageDependencyDescription {
        return .local(identity: identity,
                      name: name,
                      path: AbsolutePath(path),
                      productFilter: productFilter)
    }

    static func local(identity: PackageIdentity? = nil,
                      name: String? = nil,
                      path: AbsolutePath,
                      productFilter: ProductFilter = .everything
    ) -> PackageDependencyDescription {
        let identity = identity ?? PackageIdentity(url: path.pathString)
        return .local(identity: identity,
                      name: name,
                      path: path,
                      productFilter: productFilter)
    }

    static func scm(identity: PackageIdentity? = nil,
                    name: String? = nil,
                    location: String,
                    requirement: Requirement,
                    productFilter: ProductFilter = .everything
    ) -> PackageDependencyDescription {
        let identity = identity ?? PackageIdentity(url: location)
        return .scm(identity: identity,
                    name: name,
                    location: location,
                    requirement: requirement,
                    productFilter: productFilter)
    }
}
