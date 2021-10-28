/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import PackageModel
import TSCBasic
import enum TSCUtility.Git

/// Represents the input to the package graph root.
public struct PackageGraphRootInput {
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

    /// The root packages.
    public let packages: [PackageIdentity: (reference: PackageReference, manifest: Manifest)]

    /// The root manifests.
    public var manifests: [PackageIdentity: Manifest] {
        return self.packages.compactMapValues { $0.manifest }
    }

    /// The root package references.
    public var packageReferences: [PackageReference] {
        return self.packages.values.map { $0.reference }
    }

    /// The top level dependencies.
    public let dependencies: [PackageDependency]

    /// Create a package graph root.
    /// Note this quietly skip inputs for which manifests are not found. this could be because the manifest  failed to load or for some other reasons
    // FIXME: This API behavior wrt to non-found manifests is fragile, but required by IDEs
    // it may lead to incorrect assumption in downstream code which may expect an error if a manifest was not found
    // we should refactor this API to more clearly return errors for inputs that do not have a corresponding manifest
    public init(input: PackageGraphRootInput, manifests: [AbsolutePath: Manifest]) {
        self.packages = input.packages.reduce(into: .init(), { partial, inputPath in
            if let manifest = manifests[inputPath]  {
                let packagePath = manifest.path.parentDirectory
                let identity = PackageIdentity(path: packagePath) // this does not use the identity resolver which is fine since these are the root packages
                partial[identity] = (.root(identity: identity, path: packagePath), manifest)
            }
        })
        
        self.dependencies = input.dependencies
    }

    /// Returns the constraints imposed by root manifests + dependencies.
    public func constraints() throws -> [PackageContainerConstraint] {
        let constraints = self.packageReferences.map {
            PackageContainerConstraint(package: $0, requirement: .unversioned)
        }
        
        let depend = try dependencies.map{
            PackageContainerConstraint(
                package: $0.createPackageRef(),
                requirement: try $0.toConstraintRequirement()
            )
        }
        return constraints + depend
    }
}

extension PackageDependency {
    /// Returns the constraint requirement representation.
    public func toConstraintRequirement() throws -> PackageRequirement {
        switch self {
        case .fileSystem:
            return .unversioned
        case .sourceControl(let settings):
            return try settings.requirement.toConstraintRequirement()
        case .registry(let settings):
            return try settings.requirement.toConstraintRequirement()
        }
    }
}

extension PackageDependency.SourceControl.Requirement {
    /// Returns the constraint requirement representation.
    public func toConstraintRequirement() throws -> PackageRequirement {
        switch self {
        case .range(let range):
            return .versionSet(.range(range))
        case .revision(let identifier):
            // FIXME: this validation could/should move somewhere more appropriate
            guard Git.checkRefFormat(ref: identifier) else {
                throw StringError("Could not find revision: '\(identifier)'")
            }
            return .revision(identifier)
        case .branch(let identifier):
            // FIXME: this validation could/should move somewhere more appropriate
            guard Git.checkRefFormat(ref: identifier) else {
                throw StringError("Could not find branch: '\(identifier)'")
            }
            return .revision(identifier)
        case .exact(let version):
            return .versionSet(.exact(version))
        }
    }
}

extension PackageDependency.Registry.Requirement {
    /// Returns the constraint requirement representation.
    public func toConstraintRequirement() throws -> PackageRequirement {
        switch self {
        case .range(let range):
            return .versionSet(.range(range))
        case .exact(let version):
            return .versionSet(.exact(version))
        }
    }
}
