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

    public typealias PackageDependency = PackageGraphRoot.PackageDependency

    /// The list of root packages.
    public let packages: [AbsolutePath]

    /// Top level dependencies to the graph.
    public let dependencies: [PackageDependency]

    /// Create a package graph root.
    public init(packages: [AbsolutePath], dependencies: [PackageDependency] = []) {
        self.packages = packages
        self.dependencies = dependencies
    }
}

/// Represents the inputs to the package graph.
public struct PackageGraphRoot {

    // FIXME: We can kill this now.
    //
    /// Represents a top level package dependencies.
    public struct PackageDependency {

        public typealias Requirement = PackageModel.PackageDependencyDescription.Requirement

        // Location of this dependency.
        //
        // Opaque location object which will be included in any diagnostics
        // related to this dependency.  Clients can use this identify where this
        // dependency is declared.
        public let location: String

        /// The URL of the package.
        public let url: String

        /// The requirement of the package.
        public let requirement: Requirement

        /// The product filter to apply to the package.
        public let productFilter: ProductFilter

        /// Create the package reference object for the dependency.
        public func createPackageRef(config: SwiftPMConfig) -> PackageReference {
            let effectiveURL = config.mirroredURL(forURL: self.url)
            return PackageReference(
                identity: PackageReference.computeIdentity(packageURL: effectiveURL),
                path: effectiveURL,
                kind: requirement == .localPackage ? .local : .remote
            )
        }

        public init(
            url: String,
            requirement: Requirement,
            productFilter: ProductFilter,
            location: String
        ) {
            // FIXME: SwiftPM can't handle file URLs with file:// scheme so we need to
            // strip that. We need to design a URL data structure for SwiftPM.
            let filePrefix = "file://"
            if url.hasPrefix(filePrefix) {
                self.url = AbsolutePath(String(url.dropFirst(filePrefix.count))).pathString
            } else {
                self.url = url
            }
            self.requirement = requirement
            self.productFilter = productFilter
            self.location = location
        }
    }

    /// The list of root manifests.
    public let manifests: [Manifest]

    /// The root package references.
    public let packageRefs: [PackageReference]

    /// The top level dependencies.
    public let dependencies: [PackageDependency]

    /// Create a package graph root.
    public init(input: PackageGraphRootInput, manifests: [Manifest], explicitProduct: String? = nil) {
        self.packageRefs = zip(input.packages, manifests).map { (path, manifest) in
            let identity = PackageReference.computeIdentity(packageURL: manifest.url)
            return PackageReference(identity: identity, path: path.pathString, kind: .root)
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
            for dependency in manifests.lazy
                .map({ $0.dependenciesRequired(for: .everything) }).joined() {
                    adjustedDependencies.append(PackageDependency(
                        url: dependency.declaration.url,
                        requirement: dependency.declaration.requirement,
                        productFilter: .specific([product]),
                        location: ""))
            }
        }

        self.dependencies = adjustedDependencies
    }

    /// Returns the constraints imposed by root manifests + dependencies.
    public func constraints(config: SwiftPMConfig) -> [RepositoryPackageConstraint] {
        let constraints = packageRefs.map({
            RepositoryPackageConstraint(container: $0, requirement: .unversioned, products: .everything)
        })
        return constraints + dependencies.map({
            RepositoryPackageConstraint(
                container: $0.createPackageRef(config: config),
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
