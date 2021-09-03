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
    public let location: Location
    public let products: ProductFilter

    init(deprecatedName: String? = nil, location: Location, products: ProductFilter = .everything) {
        self.deprecatedName = deprecatedName
        self.location = location
        self.products = products
    }

    // TODO: refactor this when adding registry support
    public func convert(baseURL: AbsolutePath, identityResolver: IdentityResolver) -> PackageDependency {
        switch self.location {
        case .fileSystem(let path):
            let path = baseURL.appending(path)
            let location = identityResolver.resolveLocation(from: path.pathString)
            let identity = identityResolver.resolveIdentity(for: location)
            return .fileSystem(
                identity: identity,
                deprecatedName: self.deprecatedName,
                path: location,
                productFilter: self.products
            )
        case .sourceControlPath(let path, let requirement):
            let path = baseURL.appending(path)
            let location = identityResolver.resolveLocation(from: path.pathString)
            let identity = identityResolver.resolveIdentity(for: location)
            return .sourceControl(
                identity: identity,
                deprecatedName: self.deprecatedName,
                location: location,
                requirement: requirement,
                productFilter: self.products
            )
        case .sourceControlURL(let url, let requirement):
            let location = identityResolver.resolveLocation(from: url)
            let identity = identityResolver.resolveIdentity(for: location)
            return .sourceControl(
                identity: identity,
                deprecatedName: self.deprecatedName,
                location: location,
                requirement: requirement,
                productFilter: self.products
            )
        }
    }

    public static func fileSystem(path: String, products: ProductFilter = .everything) -> MockDependency {
        MockDependency(location: .fileSystem(path: RelativePath(path)), products: products)
    }

    public static func sourceControl(path: String, requirement: Requirement, products: ProductFilter = .everything) -> MockDependency {
        MockDependency(location: .sourceControlPath(path: RelativePath(path), requirement: requirement), products: products)
    }

    public static func sourceControlWithDeprecatedName(name: String, path: String, requirement: Requirement, products: ProductFilter = .everything) -> MockDependency {
        MockDependency(deprecatedName: name, location: .sourceControlPath(path: RelativePath(path), requirement: requirement), products: products)
    }

    public static func sourceControl(url: String, requirement: Requirement, products: ProductFilter = .everything) -> MockDependency {
        MockDependency(location: .sourceControlURL(url: url, requirement: requirement), products: products)
    }

    // for backwards compatibility
    public static func local(path: String, products: ProductFilter = .everything) -> MockDependency {
        Self.fileSystem(path: path, products: products)
    }

    // for backwards compatibility
    public static func scm(path: String, requirement: Requirement, products: ProductFilter = .everything) -> MockDependency {
        Self.sourceControl(path: path, requirement: requirement, products: products)
    }

    // for backwards compatibility
    public static func scmWithDeprecatedName(name: String, path: String, requirement: Requirement, products: ProductFilter = .everything) -> MockDependency {
        Self.sourceControlWithDeprecatedName(name: name, path: path, requirement: requirement, products: products)
    }

    public enum Location {
        case fileSystem(path: RelativePath)
        case sourceControlPath(path: RelativePath, requirement: Requirement)
        case sourceControlURL(url: String, requirement: Requirement)
    }
}
