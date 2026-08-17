//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageModel

extension PackageDependency {
    /// Create the package reference object for the dependency.
    public var packageRef: PackageReference {
        let packageKind: PackageReference.Kind
        switch self {
        case .fileSystem(let settings):
            packageKind = .fileSystem(settings.path)
        case .sourceControl(let settings):
            switch settings.location {
            case .local(let path):
                packageKind = .localSourceControl(path)
            case .remote(let url):
                packageKind = .remoteSourceControl(url)
            }
        case .registry(let settings):
            packageKind = .registry(settings.identity)
        }
        return PackageReference(identity: self.identity, kind: packageKind)
    }
}

extension Manifest {
    /// Constructs constraints of the dependencies in the raw package.
    public func dependencyConstraints(
        productFilter: ProductFilter,
        _ enabledTraits: EnabledTraits = ["default"]
    ) throws -> [PackageContainerConstraint] {
        return try self.dependenciesRequired(for: productFilter, enabledTraits).map({ dependency in
            let setter: EnabledTrait.Setter = .package(.init(identity: self.packageIdentity, name: self.displayName))
            let enabledTraitsSet: EnabledTraits
            if let dependencyTraits = dependency.traits {
                let explicitlyEnabledTraits = dependencyTraits.filter {
                    guard let condition = $0.condition else { return true }
                    return condition.isSatisfied(by: enabledTraits.names)
                }.map(\.name)
                enabledTraitsSet = EnabledTraits(explicitlyEnabledTraits, setBy: setter)
            } else {
                // Implicit default traits requested by parent.
                enabledTraitsSet = EnabledTraits(["default"], setBy: setter)
            }

            return PackageContainerConstraint(
                package: dependency.packageRef,
                requirement: try dependency.toConstraintRequirement(),
                products: dependency.productFilter,
                enabledTraits: enabledTraitsSet
            )
        })
    }
}

extension PackageContainerConstraint {
    /// Constructs a structure of dependency nodes in a package.
    /// - returns: An array of ``DependencyResolutionNode``
    internal func nodes() -> [DependencyResolutionNode] {
        switch products {
        case .everything:
            return [.root(package: self.package, enabledTraits: self.enabledTraits)]
        case .specific:
            switch products {
            case .everything:
                assertionFailure("Attempted to enumerate a root package’s product filter; root packages have no filter.")
                return []
            case .specific(let set):
                if set.isEmpty { // Pointing at the package without a particular product.
                    return [.empty(package: self.package)]
                } else {
                    return set.sorted().map { .product($0, package: self.package, enabledTraits: self.enabledTraits) }
                }
            }
        }
    }
}
