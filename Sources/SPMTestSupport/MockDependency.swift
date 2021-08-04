/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageLoading
import PackageModel
import TSCBasic

public struct MockDependency {
    public typealias Requirement = PackageDependencyDescription.Requirement

    public let name: String?
    public let path: String
    public let requirement: Requirement?
    public let products: ProductFilter

    init(name: String, requirement: Requirement?, products: ProductFilter = .everything) {
        self.name = name
        self.path = name
        self.requirement = requirement
        self.products = products
    }

    init(name: String?, path: String, requirement: Requirement?, products: ProductFilter = .everything) {
        self.name = name
        self.path = path
        self.requirement = requirement
        self.products = products
    }

    // TODO: refactor this when adding registry support
    public func convert(baseURL: AbsolutePath, identityResolver: IdentityResolver) -> PackageDependencyDescription {
        let path = baseURL.appending(RelativePath(self.path))
        let location = identityResolver.resolveLocation(from: path.pathString)
        let identity = identityResolver.resolveIdentity(for: location)
        if let requirement = self.requirement {
            return .scm(identity: identity,
                        name: self.name,
                        location: location,
                        requirement: requirement,
                        productFilter: self.products)
        } else {
            return .local(identity: identity,
                          name: self.name,
                          path: location,
                          productFilter: self.products)
        }
    }

    public static func local(name: String? = nil, path: String, products: ProductFilter = .everything) -> MockDependency{
        MockDependency(name: name, path: path, requirement: nil, products: products)
    }

    public static func local(name: String, products: ProductFilter = .everything) -> MockDependency {
        MockDependency(name: name, requirement: nil, products: products)
    }

    public static func git(name: String? = nil, path: String, requirement: Requirement, products: ProductFilter = .everything) -> MockDependency{
        MockDependency(name: name, path: path, requirement: requirement, products: products)
    }

    public static func git(name: String, requirement: Requirement, products: ProductFilter = .everything) -> MockDependency {
        MockDependency(name: name, requirement: requirement, products: products)
    }
}
