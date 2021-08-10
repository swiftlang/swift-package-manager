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
    public typealias Requirement = PackageDependency.SourceControl.Requirement

    public let deprecatedName: String?
    public let path: String
    public let requirement: Requirement?
    public let products: ProductFilter
    
    init(deprecatedName: String? = nil, path: String, requirement: Requirement?, products: ProductFilter = .everything) {
        self.deprecatedName = deprecatedName
        self.path = path
        self.requirement = requirement
        self.products = products
    }
    
    // TODO: refactor this when adding registry support
    public func convert(baseURL: AbsolutePath, identityResolver: IdentityResolver) -> PackageDependency {
        let path = baseURL.appending(RelativePath(self.path))
        let location = identityResolver.resolveLocation(from: path.pathString)
        let identity = identityResolver.resolveIdentity(for: location)
        if let requirement = self.requirement {
            return .scm(identity: identity,
                        deprecatedName: self.deprecatedName,
                        location: location,
                        requirement: requirement,
                        productFilter: self.products)
        } else {
            return .local(identity: identity,
                          deprecatedName: self.deprecatedName,
                          path: location,
                          productFilter: self.products)
        }
    }
    
    public static func local(path: String, products: ProductFilter = .everything) -> MockDependency {
        MockDependency(path: path, requirement: nil, products: products)
    }

    public static func scm(path: String, requirement: Requirement, products: ProductFilter = .everything) -> MockDependency {
        MockDependency(path: path, requirement: requirement, products: products)
    }

    public static func scmWithDeprecatedName(name: String, path: String, requirement: Requirement, products: ProductFilter = .everything) -> MockDependency {
        MockDependency(deprecatedName: name, path: path, requirement: requirement, products: products)
    }

}
