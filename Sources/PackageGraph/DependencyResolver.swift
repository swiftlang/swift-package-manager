/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import struct PackageModel.PackageReference
import struct TSCUtility.Version
import class Foundation.NSDate

public enum DependencyResolverError: Error, Equatable, CustomStringConvertible {
     /// A revision-based dependency contains a local package dependency.
    case revisionDependencyContainsLocalPackage(dependency: String, localPackage: String)

    public static func == (lhs: DependencyResolverError, rhs: DependencyResolverError) -> Bool {
        switch (lhs, rhs) {
        case (.revisionDependencyContainsLocalPackage(let a1, let b1), .revisionDependencyContainsLocalPackage(let a2, let b2)):
            return a1 == a2 && b1 == b2
        }
    }

    public var description: String {
        switch self {
        case .revisionDependencyContainsLocalPackage(let dependency, let localPackage):
            return "package '\(dependency)' is required using a revision-based requirement and it depends on local package '\(localPackage)', which is not supported"
        }
    }
}

/// A requirement that a package must satisfy.
public enum PackageRequirement: Hashable {

    /// The requirement is specified by the version set.
    case versionSet(VersionSetSpecifier)

    /// The requirement is specified by the revision.
    ///
    /// The revision string (identifier) should be valid and present in the
    /// container. Only one revision requirement per container is possible
    /// i.e. two revision requirements for same container will lead to
    /// unsatisfiable resolution. The revision requirement can either come
    /// from initial set of constraints or from dependencies of a revision
    /// requirement.
    case revision(String)

    /// Un-versioned requirement i.e. a version should not resolved.
    case unversioned
}

extension PackageRequirement: CustomStringConvertible {
    public var description: String {
        switch self {
        case .versionSet(let versionSet): return versionSet.description
        case .revision(let revision): return revision
        case .unversioned: return "unversioned"
        }
    }
}

/// A container of packages.
///
/// This is the top-level unit of package resolution, i.e. the unit at which
/// versions are associated.
///
/// It represents a package container (e.g., a source repository) which can be
/// identified unambiguously and which contains a set of available package
/// versions and the ability to retrieve the dependency constraints for each of
/// those versions.
///
/// We use the "container" terminology here to differentiate between two
/// conceptual notions of what the package is: (1) informally, the repository
/// containing the package, but from which a package cannot be loaded by itself
/// and (2) the repository at a particular version, at which point the package
/// can be loaded and dependencies enumerated.
///
/// This is also designed in such a way to extend naturally to multiple packages
/// being contained within a single repository, should we choose to support that
/// later.
public protocol PackageContainer {

    /// The identifier for the package.
    var identifier: PackageReference { get }

    /// Returns true if the tools version is compatible at the given version.
    func isToolsVersionCompatible(at version: Version) -> Bool

    /// Get the list of versions which are available for the package.
    ///
    /// The list will be returned in sorted order, with the latest version *first*.
    /// All versions will not be requested at once. Resolver will request the next one only
    /// if the previous one did not satisfy all constraints.
    func versions(filter isIncluded: (Version) -> Bool) -> AnySequence<Version>

    /// Get the list of versions in the repository sorted in the reverse order, that is the latest
    /// version appears first.
    var reversedVersions: [Version] { get }

    // FIXME: We should perhaps define some particularly useful error codes
    // here, so the resolver can handle errors more meaningfully.
    //
    /// Fetch the declared dependencies for a particular version.
    ///
    /// This property is expected to be efficient to access, and cached by the
    /// client if necessary.
    ///
    /// - Precondition: `versions.contains(version)`
    /// - Throws: If the version could not be resolved; this will abort
    ///   dependency resolution completely.
    func getDependencies(at version: Version) throws -> [PackageContainerConstraint]

    /// Fetch the declared dependencies for a particular revision.
    ///
    /// This property is expected to be efficient to access, and cached by the
    /// client if necessary.
    ///
    /// - Throws: If the revision could not be resolved; this will abort
    ///   dependency resolution completely.
    func getDependencies(at revision: String) throws -> [PackageContainerConstraint]

    /// Fetch the dependencies of an unversioned package container.
    ///
    /// NOTE: This method should not be called on a versioned container.
    func getUnversionedDependencies() throws -> [PackageContainerConstraint]

    /// Get the updated identifier at a bound version.
    ///
    /// This can be used by the containers to fill in the missing information that is obtained
    /// after the container is available. The updated identifier is returned in result of the
    /// dependency resolution.
    func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> PackageReference
}

/// An interface for resolving package containers.
public protocol PackageContainerProvider {
    /// Get the container for a particular identifier asynchronously.
    func getContainer(
        for identifier: PackageReference,
        skipUpdate: Bool,
        completion: @escaping (Result<PackageContainer, Swift.Error>) -> Void
    )
}

/// An individual constraint onto a container.
public struct PackageContainerConstraint: CustomStringConvertible, Equatable, Hashable {

    /// The identifier for the container the constraint is on.
    public let identifier: PackageReference

    /// The constraint requirement.
    public let requirement: PackageRequirement

    /// Create a constraint requiring the given `container` satisfying the
    /// `requirement`.
    public init(container identifier: PackageReference, requirement: PackageRequirement) {
        self.identifier = identifier
        self.requirement = requirement
    }

    /// Create a constraint requiring the given `container` satisfying the
    /// `versionRequirement`.
    public init(container identifier: PackageReference, versionRequirement: VersionSetSpecifier) {
        self.init(container: identifier, requirement: .versionSet(versionRequirement))
    }

    public var description: String {
        return "Constraint(\(identifier), \(requirement))"
    }
}

/// Delegate interface for dependency resoler status.
public protocol DependencyResolverDelegate {
}

/// A bound version for a package within an assignment.
public enum BoundVersion: Equatable, CustomStringConvertible {
    /// The assignment should not include the package.
    ///
    /// This is different from the absence of an assignment for a particular
    /// package, which only indicates the assignment is agnostic to its
    /// version. This value signifies the package *may not* be present.
    case excluded

    /// The version of the package to include.
    case version(Version)

    /// The package assignment is unversioned.
    case unversioned

    /// The package assignment is this revision.
    case revision(String)

    public var description: String {
        switch self {
        case .excluded:
            return "excluded"
        case .version(let version):
            return version.description
        case .unversioned:
            return "unversioned"
        case .revision(let identifier):
            return identifier
        }
    }
}

public class DependencyResolver {
    public typealias Binding = (container: PackageReference, binding: BoundVersion)

    /// The dependency resolver result.
    public enum Result {
        /// A valid and complete assignment was found.
        case success([Binding])

        /// The resolver encountered an error during resolution.
        case error(Swift.Error)
    }
}
