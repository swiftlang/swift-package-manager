/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import Utility

import PackageModel
import PackageDescription4
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

    /// Represents a top level package dependencies.
    public struct PackageDependency {

        public typealias Requirement = PackageDescription4.Package.Dependency.Requirement

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

        /// Create the package reference object for the dependency.
        public func createPackageRef() -> PackageReference {
            return PackageReference(
                identity: PackageReference.computeIdentity(packageURL: url),
                path: url
            )
        }

        public init(
            url: String,
            requirement: Requirement,
            location: String
        ) {
            // FIXME: SwiftPM can't handle file URLs with file:// scheme so we need to
            // strip that. We need to design a URL data structure for SwiftPM.
            let filePrefix = "file://"
            if url.hasPrefix(filePrefix) {
                self.url = AbsolutePath(String(url.dropFirst(filePrefix.count))).asString
            } else {
                self.url = url
            }
            self.requirement = requirement
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
    public init(input: PackageGraphRootInput, manifests: [Manifest]) {
        self.packageRefs = zip(input.packages, manifests).map { (path, manifest) in
            PackageReference(identity: manifest.name.lowercased(), path: path.asString, isLocal: true)
        }
        self.manifests = manifests
        self.dependencies = input.dependencies
    }

    /// Returns the constraints imposed by root manifests + dependencies.
    public var constraints: [RepositoryPackageConstraint] {
        let constraints = packageRefs.map({
            RepositoryPackageConstraint(container: $0, requirement: .unversioned)
        })
        return constraints + dependencies.map({
            RepositoryPackageConstraint(
                container: $0.createPackageRef(),
                requirement: $0.requirement.toConstraintRequirement()
            )
        })
    }
}

extension PackageDescription4.Package.Dependency.Requirement {

    /// Returns the constraint requirement representation.
    public func toConstraintRequirement() -> RepositoryPackageConstraint.Requirement {
        switch self {
        case .rangeItem(let range):
            return .versionSet(.range(range.asUtilityVersion))

        case .revisionItem(let identifier):
            assert(identifier.count == 40)
            assert(Git.checkRefFormat(ref: identifier))

            return .revision(identifier)

        case .branchItem(let identifier):
            assert(Git.checkRefFormat(ref: identifier))

            return .revision(identifier)

        case .exactItem(let version):
            return .versionSet(.exact(Version(pdVersion: version)))
        }
    }
}
