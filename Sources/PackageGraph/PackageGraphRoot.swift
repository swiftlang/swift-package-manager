/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
import TSCUtility

import PackageModel
import SourceControl

/// Represents the input to the package graph root.
public struct PackageGraphRootInput {
    /// The list of root packages.
    public let packages: [AbsolutePath]

    /// Top level dependencies to the graph.
    public let dependencies: [PackageDependencyDescription]

    /// Dependency mirrors for the graph.
    public let mirrors: DependencyMirrors

    /// Create a package graph root.
    public init(packages: [AbsolutePath], dependencies: [PackageDependencyDescription] = [], mirrors: DependencyMirrors = [:]) {
        self.packages = packages
        self.dependencies = dependencies
        self.mirrors = mirrors
    }
}

/// Represents the inputs to the package graph.
public struct PackageGraphRoot {

    /// The list of root manifests.
    public let manifests: [Manifest]

    /// The root package references.
    public let packageRefs: [PackageReference]

    /// The top level dependencies.
    public let dependencies: [PackageDependencyDescription]

    /// Create a package graph root.
    public init(input: PackageGraphRootInput, manifests: [Manifest], explicitProduct: String? = nil) {
        self.packageRefs = zip(input.packages, manifests).map { (path, manifest) in
            let identity = PackageIdentity(url: manifest.url)
            return .root(identity: identity, path: path)
        }
        self.manifests = manifests

        // FIXME: Deprecate special casing once the manifest supports declaring used executable products.
        // Special casing explicit products like this is necessary to pass the test suite and satisfy backwards compatibility.
        // However, changing the dependencies based on the command line arguments may force pins to temporarily change,
        // which can become a nuissance.
        // Such pin switching can currently be worked around by declaring the executable product as a dependency of a dummy target.
        // But in the future it might be worth providing a way of declaring them in the manifest without a dummy target,
        // at which time the current special casing can be deprecated.
        var adjustedDependencies = input.dependencies
        if let product = explicitProduct {
            for dependency in manifests.lazy.map({ $0.dependenciesRequired(for: .everything) }).joined() {
                adjustedDependencies.append(dependency.filtered(by: .specific([product])))
            }
        }

        self.dependencies = adjustedDependencies
    }

    /// Returns the constraints imposed by root manifests + dependencies.
    public func constraints(mirrors: DependencyMirrors) -> [PackageContainerConstraint] {
        let constraints = packageRefs.map({
            PackageContainerConstraint(package: $0, requirement: .unversioned, products: .everything)
        })
        return constraints + dependencies.map({
            PackageContainerConstraint(
                package: $0.createPackageRef(mirrors: mirrors),
                requirement: $0.requirement.toConstraintRequirement(),
                products: $0.productFilter
            )
        })
    }
}

extension PackageDependencyDescription.Requirement {

    /// Returns the constraint requirement representation.
    public func toConstraintRequirement() -> PackageRequirement {
        switch self {
        case .range(let range):
            return .versionSet(.range(range))

        case .revision(let identifier):
            assert(Git.checkRefFormat(ref: identifier))

            return .revision(identifier)

        case .branch(let identifier):
            assert(Git.checkRefFormat(ref: identifier))

            return .revision(identifier)

        case .exact(let version):
            return .versionSet(.exact(version))

        case .localPackage:
            return .unversioned
        }
    }
}
