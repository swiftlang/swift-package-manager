/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel
import SourceControl

extension PackageDependencyDescription {
    /// Create the package reference object for the dependency.
    public func createPackageRef(config: SwiftPMConfig) -> PackageReference {
        let effectiveURL = config.mirroredURL(forURL: self.url)
        return PackageReference(
            identity: PackageReference.computeIdentity(packageURL: effectiveURL),
            path: effectiveURL,
            kind: requirement == .localPackage ? .local : .remote
        )
    }
}

extension Manifest {

    /// Constructs constraints of the dependencies in the raw package.
    public func dependencyConstraints(productFilter: ProductFilter, config: SwiftPMConfig) -> [RepositoryPackageConstraint] {
        return dependenciesRequired(for: productFilter).map({
            return RepositoryPackageConstraint(
                container: $0.declaration.createPackageRef(config: config),
                requirement: $0.declaration.requirement.toConstraintRequirement(),
                products: $0.productFilter)
        })
    }
}

extension RepositoryPackageConstraint {

    internal func nodes() -> [DependencyResolutionNode] {
        switch products {
        case .everything:
            return [.root(package: identifier)]
        case .specific:
            switch products {
            case .everything:
                fatalError("Attempted to enumerate a root package’s product filter; root packages have no filter.")
            case .specific(let set):
                if set.isEmpty { // Pointing at the package without a particular product.
                    return [.empty(package: identifier)]
                } else {
                    return set.sorted().map { .product($0, package: identifier) }
                }
            }
        }
    }
}
